//! Unix 回执描述符只在目标子进程中清除 CLOEXEC，父进程始终保留关闭边界。
use super::*;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
#[cfg(not(any(target_os = "linux", target_os = "android")))]
use std::process::{Child, Command};
#[cfg(any(target_os = "linux", target_os = "android"))]
#[path = "linux.rs"]
mod linux;
#[cfg(any(target_os = "linux", target_os = "android"))]
#[path = "supervised.rs"]
mod supervised;
#[cfg(any(target_os = "linux", target_os = "android"))]
pub(in crate::api) use supervised::Process;
#[cfg(any(target_os = "linux", target_os = "android"))]
pub(super) use supervised::spawn;
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub(in crate::api) struct Process {
    child: Child,
    identity_lost: bool,
    #[cfg(test)]
    fail_termination: u32,
}
#[cfg(not(any(target_os = "linux", target_os = "android")))]
impl Process {
    #[cfg(test)]
    pub(in crate::api) fn fail_terminations(&mut self, count: u32) {
        self.fail_termination = count;
    }
    pub(in crate::api) fn id(&self) -> Option<u32> {
        Some(self.child.id())
    }
    pub(in crate::api) fn terminate(&mut self) -> io::Result<()> {
        #[cfg(test)]
        if self.fail_termination > 0 {
            self.fail_termination -= 1;
            return Err(io::Error::other("测试：实际终止调用失败"));
        }
        if self.identity_lost {
            return Err(io::Error::other(
                "子进程退出状态已被其它运行时消费，不能再按 PID 终止",
            ));
        }
        self.child.kill()
    }
    pub(in crate::api) async fn wait(&mut self) -> io::Result<Option<i32>> {
        if self.identity_lost {
            return Err(io::Error::from_raw_os_error(libc::ECHILD));
        }
        loop {
            match self.child.try_wait() {
                Ok(Some(exit)) => return Ok(exit.code()),
                Ok(None) => tokio::time::sleep(std::time::Duration::from_millis(10)).await,
                Err(error) => {
                    if error.raw_os_error() == Some(libc::ECHILD) {
                        self.identity_lost = true;
                    }
                    return Err(error);
                }
            }
        }
    }
}
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub(super) async fn spawn(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    ack: bool,
) -> io::Result<Spawned> {
    let mut command = Command::new(executable);
    command.envs(environment);
    let (input, child_input) = stdio_pair()?;
    let (output, child_output) = stdio_pair()?;
    let (error, child_error) = stdio_pair()?;
    command.stdin(std::process::Stdio::from(child_input));
    command.stdout(std::process::Stdio::from(child_output));
    command.stderr(std::process::Stdio::from(child_error));
    let pipe = configure_ack(&mut command, ack)?;
    command.args(arguments);
    let child = command.spawn()?;
    drop(command);
    // 不使用 Tokio Child，避免丢失回执后进入按 PID 回收的后台孤儿队列。
    let input = Box::pin(input);
    let output = Box::pin(output);
    let error = Box::pin(error);
    let ack = pipe.map(|(read, write)| {
        drop(write);
        read
    });
    Ok(Spawned {
        process: Process {
            child,
            identity_lost: false,
            #[cfg(test)]
            fail_termination: 0,
        },
        input,
        output,
        error,
        ack,
    })
}
/// 传入 exec 的私有能力不能占用标准流编号，否则 stdio 的 dup 会覆盖其身份。
fn private_fd(fd: OwnedFd) -> io::Result<OwnedFd> {
    if fd.as_raw_fd() >= 3 {
        return Ok(fd);
    }
    let duplicated = unsafe { libc::fcntl(fd.as_raw_fd(), libc::F_DUPFD_CLOEXEC, 3) };
    if duplicated == -1 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe { OwnedFd::from_raw_fd(duplicated) })
}
#[cfg(any(target_os = "linux", target_os = "android"))]
fn private_stream_pair() -> io::Result<(
    std::os::unix::net::UnixStream,
    std::os::unix::net::UnixStream,
)> {
    let (parent, child) = std::os::unix::net::UnixStream::pair()?;
    let parent = std::os::unix::net::UnixStream::from(private_fd(parent.into())?);
    let child = std::os::unix::net::UnixStream::from(private_fd(child.into())?);
    Ok((parent, child))
}
fn stdio_pair() -> io::Result<(tokio::net::UnixStream, OwnedFd)> {
    let (parent, child) = std::os::unix::net::UnixStream::pair()?;
    // 父端可占用宿主已关闭的标准流；子端作为 dup 的来源，必须避开目标编号。
    // 保留父端编号也避免 Command 自用的 exec 错误管道落入随后被 dup 覆盖的标准流。
    let child = private_fd(child.into())?;
    parent.set_nonblocking(true)?;
    Ok((tokio::net::UnixStream::from_std(parent)?, child))
}
fn configure_ack(
    command: &mut std::process::Command,
    ack: bool,
) -> io::Result<Option<(Reader, OwnedFd)>> {
    use std::os::unix::process::CommandExt;
    Ok(if ack {
        let (read, write) = ack_pipe()?;
        let read = private_fd(read)?;
        let write = private_fd(write)?;
        let fd = write.as_raw_fd();
        command.args(["--reply-fd".to_owned(), fd.to_string()]);
        unsafe {
            command.pre_exec(move || {
                if libc::fcntl(fd, libc::F_SETFD, 0) == -1 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let flags = unsafe { libc::fcntl(read.as_raw_fd(), libc::F_GETFL) };
        if flags == -1
            || unsafe { libc::fcntl(read.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK) }
                == -1
        {
            return Err(io::Error::last_os_error());
        }
        // 所有会失败的 ACK 配置都在 spawn 前完成，Child 一旦产生就必定交给监督任务。
        // ACK reader 独占此 FD，注册期间只通过 AsyncFd 执行非阻塞读取。
        let reader = unsafe { tokio::io::unix::AsyncFd::register(read) }
            .map_err(|error| io::Error::other(error.to_string()))?;
        Some((Box::pin(AckReader(reader)) as Reader, write))
    } else {
        None
    })
}
#[cfg(any(target_os = "linux", target_os = "android"))]
fn ack_pipe() -> io::Result<(OwnedFd, OwnedFd)> {
    let mut descriptors = [-1; 2];
    // 原子设置 CLOEXEC，避免并发创建无关子进程时泄露 ACK 两端。
    if unsafe { libc::pipe2(descriptors.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe {
        (
            OwnedFd::from_raw_fd(descriptors[0]),
            OwnedFd::from_raw_fd(descriptors[1]),
        )
    })
}
#[cfg(not(any(target_os = "linux", target_os = "android")))]
fn ack_pipe() -> io::Result<(OwnedFd, OwnedFd)> {
    use std::os::unix::{ffi::OsStrExt, fs::OpenOptionsExt};
    // Darwin 没有 pipe2；私有 FIFO 的两次 open 均原子设置 CLOEXEC，避免 pipe+fcntl 继承窗口。
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("ack");
    let name = std::ffi::CString::new(path.as_os_str().as_bytes()).map_err(io::Error::other)?;
    if unsafe { libc::mkfifo(name.as_ptr(), 0o600) } != 0 {
        return Err(io::Error::last_os_error());
    }
    let read = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
        .open(&path)?;
    let write = std::fs::OpenOptions::new()
        .write(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
        .open(&path)?;
    std::fs::remove_file(path)?;
    Ok((read.into(), write.into()))
}
struct AckReader(tokio::io::unix::AsyncFd<OwnedFd>);
impl AsyncRead for AckReader {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<io::Result<()>> {
        loop {
            let mut ready = std::task::ready!(self.0.poll_read_ready(cx))?;
            match ready.try_io(|fd| {
                let bytes = buffer.initialize_unfilled();
                let read =
                    unsafe { libc::read(fd.as_raw_fd(), bytes.as_mut_ptr().cast(), bytes.len()) };
                if read < 0 {
                    return Err(io::Error::last_os_error());
                }
                buffer.advance(read as usize);
                Ok(())
            }) {
                Ok(result) => return std::task::Poll::Ready(result),
                Err(_) => continue,
            }
        }
    }
}
