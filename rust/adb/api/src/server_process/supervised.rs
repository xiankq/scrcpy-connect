//! 实际 CLI 由独立监督器独占 waitstatus；pidfd 只证明监督器自己的退出。
use super::*;
use std::{
    io::Write,
    sync::{Arc, Mutex},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::UnixStream,
};
#[allow(dead_code)]
#[path = "../../supervisor/protocol.rs"]
mod protocol;
use protocol::{Event, Launch};
static EXECUTABLE: Mutex<Option<Arc<OwnedFd>>> = Mutex::new(None);
pub(in crate::api) struct Process {
    supervisor: linux::Process,
    control: UnixStream,
    buffer: Vec<u8>,
    pid: Option<u32>,
    exit: Option<Option<i32>>,
    broken: Option<String>,
    #[cfg(test)]
    fail_termination: u32,
}
impl Process {
    #[cfg(test)]
    pub(in crate::api) fn fail_terminations(&mut self, count: u32) {
        self.fail_termination = count;
    }
    pub(in crate::api) fn id(&self) -> Option<u32> {
        self.pid
    }
    pub(in crate::api) fn terminate(&mut self) -> io::Result<()> {
        #[cfg(test)]
        if self.fail_termination > 0 {
            self.fail_termination -= 1;
            return Err(io::Error::other("测试：实际终止调用失败"));
        }
        // 只通知真正持有 CLI Child 的监督器，不能先杀监督器而丢失孙进程所有者。
        let byte = protocol::STOP;
        let result = unsafe {
            libc::send(
                self.control.as_raw_fd(),
                (&byte as *const u8).cast(),
                1,
                libc::MSG_DONTWAIT | libc::MSG_NOSIGNAL,
            )
        };
        if result == 1 {
            return Ok(());
        }
        if self.exit.is_some() {
            return Ok(());
        }
        Err(io::Error::last_os_error())
    }
    pub(in crate::api) async fn wait(&mut self) -> io::Result<Option<i32>> {
        if let Some(message) = &self.broken {
            return Err(io::Error::other(message.clone()));
        }
        while self.exit.is_none() {
            match self.next_event().await {
                Ok(Event::Started(pid)) => self.pid = Some(pid),
                Ok(Event::Exited(code)) => self.exit = Some(code),
                Ok(Event::TerminationFailed(message)) => return Err(io::Error::other(message)),
                Ok(Event::StartFailed(message)) => return Err(io::Error::other(message)),
                Err(error) => {
                    // helper 自身退出不证明目标已退出，协议丢失后始终保留未知及原登记。
                    self.broken = Some(format!("监督协议未确认目标退出：{error}"));
                    return Err(io::Error::other(self.broken.clone().expect("已保存故障")));
                }
            }
        }
        self.supervisor.wait().await?;
        Ok(self.exit.expect("目标已明确退出"))
    }
    async fn next_event(&mut self) -> io::Result<Event> {
        loop {
            if self.buffer.len() >= 4 {
                let size =
                    u32::from_be_bytes(self.buffer[..4].try_into().expect("已读帧头")) as usize;
                if size > protocol::MAX_FRAME {
                    return Err(io::Error::other("监督回执帧过大"));
                }
                if self.buffer.len() >= size + 4 {
                    let event = Event::decode(&self.buffer[4..size + 4])?;
                    self.buffer.drain(..size + 4);
                    return Ok(event);
                }
            }
            let mut bytes = [0; 8192];
            let size = self.control.read(&mut bytes).await?;
            if size == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "监督控制流已结束",
                ));
            }
            self.buffer.extend_from_slice(&bytes[..size]);
        }
    }
}
pub(in crate::api) async fn spawn(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    ack: bool,
) -> io::Result<Spawned> {
    let helper = executable_fd()?;
    let (parent, child) = private_stream_pair()?;
    parent.set_nonblocking(true)?;
    let control = UnixStream::from_std(parent)?;
    let mut target = std::process::Command::new(executable);
    let pipe = configure_ack(&mut target, ack)?;
    target.args(arguments);
    let arguments = target
        .get_args()
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let ack_fd = pipe.as_ref().map(|(_, write)| write.as_raw_fd());
    let launch = Launch {
        executable: executable.to_owned(),
        arguments,
        environment: environment.clone(),
        ack_fd,
    };
    let frame = launch.encode()?;
    let mut inherited = vec![child.as_raw_fd()];
    if let Some(fd) = ack_fd {
        inherited.push(fd);
    }
    let spawned = linux::spawn_inheriting(
        &format!("/proc/self/fd/{}", helper.as_raw_fd()),
        &["--control-fd".into(), child.as_raw_fd().to_string()],
        environment,
        &inherited,
    )
    .await?;
    drop(child);
    let linux::Spawned {
        process: supervisor,
        input,
        output,
        error,
        ..
    } = spawned;
    let mut process = Process {
        supervisor,
        control,
        buffer: Vec::new(),
        pid: None,
        exit: None,
        broken: None,
        #[cfg(test)]
        fail_termination: 0,
    };
    let write = process.control.write_all(&frame).await;
    let first = match write {
        Ok(()) => tokio::time::timeout(std::time::Duration::from_secs(7), process.next_event())
            .await
            .ok(),
        Err(error) => Some(Err(error)),
    };
    match first {
        Some(Ok(Event::Started(pid))) => process.pid = Some(pid),
        Some(Ok(Event::StartFailed(message))) => {
            // 只有监督器明确报告 spawn 失败，才可返回 StartFailed 而不保留目标所有权。
            process.supervisor.wait().await?;
            return Err(io::Error::other(message));
        }
        Some(Ok(Event::Exited(code))) => process.exit = Some(code),
        Some(Ok(Event::TerminationFailed(message))) => process.broken = Some(message),
        Some(Err(error)) => {
            process.broken = Some(format!(
                "监督器 {:?} 的目标启动回执未知：{error}",
                process.supervisor.id()
            ))
        }
        None => {} // 启动未完成仍交付精确监督器，取消与清理可继续等待其真实回执。
    }
    Ok(Spawned {
        process,
        input,
        output,
        error,
        ack: pipe.map(|(read, write)| {
            drop(write);
            read
        }),
    })
}
fn executable_fd() -> io::Result<Arc<OwnedFd>> {
    let mut slot = EXECUTABLE.lock().expect("监督器镜像");
    if let Some(fd) = slot.as_ref() {
        return Ok(fd.clone());
    }
    let name = c"interop-adb-supervisor";
    let flags = libc::MFD_CLOEXEC | libc::MFD_ALLOW_SEALING;
    // 新内核显式声明可执行；旧内核不认识 MFD_EXEC 时只回退到其原有 memfd 语义。
    let mut raw =
        unsafe { libc::syscall(libc::SYS_memfd_create, name.as_ptr(), flags | 0x10) } as i32;
    if raw < 0 && io::Error::last_os_error().raw_os_error() == Some(libc::EINVAL) {
        raw = unsafe { libc::syscall(libc::SYS_memfd_create, name.as_ptr(), flags) } as i32;
    }
    if raw < 0 {
        return Err(io::Error::last_os_error());
    }
    let fd = private_fd(unsafe { OwnedFd::from_raw_fd(raw) })?;
    let mut file = std::fs::File::from(fd);
    file.write_all(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/interop-adb-supervisor"
    )))?;
    let seals = libc::F_SEAL_WRITE | libc::F_SEAL_GROW | libc::F_SEAL_SHRINK | libc::F_SEAL_SEAL;
    if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_ADD_SEALS, seals) } == -1 {
        return Err(io::Error::last_os_error());
    }
    let fd = Arc::new(OwnedFd::from(file));
    *slot = Some(fd.clone());
    Ok(fd)
}
