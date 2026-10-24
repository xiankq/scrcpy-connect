//! pidfd 在子进程自身创建，再经私有套接字交付；不根据可复用 PID 回查进程。
use super::*;
use std::os::unix::process::CommandExt;
use tokio::io::{AsyncWriteExt, Interest};
use tokio::net::UnixStream;

pub(in crate::api) struct Spawned {
    pub process: Process,
    pub input: Writer,
    pub output: Reader,
    pub error: Reader,
}
pub(in crate::api) struct Process {
    pidfd: OwnedFd,
    pid: Option<u32>,
    exit: Option<Option<i32>>,
}
impl Process {
    pub(in crate::api) fn id(&self) -> Option<u32> {
        self.pid
    }
    #[cfg(test)]
    pub(in crate::api) fn terminate(&mut self) -> io::Result<()> {
        let result = unsafe {
            libc::syscall(
                libc::SYS_pidfd_send_signal,
                self.pidfd.as_raw_fd(),
                libc::SIGKILL,
                std::ptr::null::<libc::siginfo_t>(),
                0,
            )
        };
        if result == 0 {
            return Ok(());
        }
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            Ok(())
        } else {
            Err(error)
        }
    }
    pub(in crate::api) async fn wait(&mut self) -> io::Result<Option<i32>> {
        if let Some(exit) = self.exit {
            return Ok(exit);
        }
        loop {
            let mut poll = libc::pollfd {
                fd: self.pidfd.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            };
            let ready = unsafe { libc::poll(&mut poll, 1, 0) };
            if ready < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if poll.revents & libc::POLLNVAL != 0 {
                return Err(io::Error::other("原进程 pidfd 已失效"));
            }
            if ready > 0 && poll.revents & (libc::POLLIN | libc::POLLHUP) == 0 {
                return Err(io::Error::other("原进程 pidfd 未给出退出事件"));
            }
            if ready > 0 {
                // 先由原 pidfd 证实退出，再读取状态。其它运行时已消费 waitstatus 时只能报告未知退出码。
                let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
                let result = unsafe {
                    libc::waitid(
                        3 as libc::idtype_t,
                        self.pidfd.as_raw_fd() as libc::id_t,
                        &mut info,
                        libc::WEXITED | libc::WNOHANG,
                    )
                };
                let exit = if result == 0 {
                    if info.si_code == libc::CLD_EXITED {
                        Some(unsafe { info.si_status() })
                    } else {
                        None
                    }
                } else {
                    let error = io::Error::last_os_error();
                    if error.raw_os_error() != Some(libc::ECHILD) {
                        return Err(error);
                    }
                    None
                };
                self.exit = Some(exit);
                return Ok(exit);
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    }
}

#[cfg(test)]
pub(in crate::api) async fn spawn(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    _ack: bool,
) -> io::Result<Spawned> {
    spawn_inheriting(executable, arguments, environment, &[]).await
}
pub(in crate::api) async fn spawn_inheriting(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    inherited: &[libc::c_int],
) -> io::Result<Spawned> {
    let mut command = std::process::Command::new(executable);
    command.envs(environment);
    // 先创建并注册所有本机 I/O。产生子进程以后不再有可能遗失监督权的注册步骤。
    let (input, child_input) = stdio_pair()?;
    let (output, child_output) = stdio_pair()?;
    let (error, child_error) = stdio_pair()?;
    command.stdin(std::process::Stdio::from(child_input));
    command.stdout(std::process::Stdio::from(child_output));
    command.stderr(std::process::Stdio::from(child_error));
    let descriptors = inherited.to_vec();
    unsafe {
        command.pre_exec(move || {
            for fd in &descriptors {
                if libc::fcntl(*fd, libc::F_SETFD, 0) == -1 {
                    return Err(io::Error::last_os_error());
                }
            }
            Ok(())
        });
    }
    command.args(arguments);
    let (parent, child) = private_stream_pair()?;
    parent.set_nonblocking(true)?;
    let mut parent = UnixStream::from_std(parent)?;
    let parent_fd = parent.as_raw_fd();
    let child_fd = child.as_raw_fd();
    unsafe {
        command.pre_exec(move || {
            // fork 后父端的副本必须关闭，父监督器消失才会给此处真实 EOF。
            libc::close(parent_fd);
            let pidfd = libc::syscall(libc::SYS_pidfd_open, libc::getpid(), 0) as libc::c_int;
            if pidfd < 0 {
                return Err(io::Error::last_os_error());
            }
            let result = send_capability(child_fd, pidfd);
            libc::close(pidfd);
            result?;
            let mut acknowledgement = 0u8;
            let received = loop {
                let result = libc::recv(child_fd, (&mut acknowledgement as *mut u8).cast(), 1, 0);
                if result == -1 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                break result;
            };
            if received != 1 || acknowledgement != 1 {
                return Err(io::Error::from_raw_os_error(libc::ECANCELED));
            }
            libc::close(child_fd);
            Ok(())
        });
    }
    // spawn 会等待 pre_exec 完成；与父端交付并发，不能阻塞 Tokio 工作线程。
    let mut worker = tokio::task::spawn_blocking(move || {
        let result = command.spawn();
        drop(command);
        drop(child);
        result
    });
    let capability = tokio::select! {
        result = parent.async_io(Interest::READABLE, || receive_capability(parent.as_raw_fd())) => result,
        result = &mut worker => {
            return match result {
                Ok(Err(error)) => Err(error),
                _ => Err(io::Error::other("子进程未交付原生监督能力")),
            };
        }
    };
    let pidfd = match capability {
        Ok(fd) => fd,
        Err(error) => {
            // 没有确认就不会 exec；关闭控制端唤醒 pre_exec 后等待 spawn 真正收尾。
            drop(parent);
            let _ = worker.await;
            return Err(error);
        }
    };
    let mut process = Process {
        pidfd,
        pid: None,
        exit: None,
    };
    if let Err(error) = parent.write_all(&[1]).await {
        drop(parent);
        let _ = worker.await;
        process.wait().await?;
        return Err(error);
    }
    drop(parent);
    match worker.await {
        Ok(Ok(child)) => {
            process.pid = Some(child.id());
            // std Child 的 Drop 不按 PID 杀进程，也不会加入 Tokio 的 PID 孤儿队列。
            drop(child);
        }
        Ok(Err(error)) => {
            process.wait().await?;
            return Err(error);
        }
        Err(_) => {
            // 能力已交付，worker 异常仍保留精确监督权，交由上层真实排空而非冒充未启动。
            // 此处不丢弃 Process；上层仍可按持有的 pidfd 取消、等待并保留失败重试权。
        }
    }
    Ok(Spawned {
        process,
        input: Box::pin(input),
        output: Box::pin(output),
        error: Box::pin(error),
    })
}

// pre_exec 仅执行系统调用与栈上操作；所有握手内存均在固定大小缓冲区中。
unsafe fn send_capability(socket: libc::c_int, pidfd: libc::c_int) -> io::Result<()> {
    unsafe {
        let mut info: libc::siginfo_t = std::mem::zeroed();
        let check = libc::waitid(
            3 as libc::idtype_t,
            pidfd as libc::id_t,
            &mut info,
            libc::WEXITED | libc::WNOHANG,
        );
        if check != -1 || io::Error::last_os_error().raw_os_error() != Some(libc::ECHILD) {
            return Err(io::Error::from_raw_os_error(libc::ENOTSUP));
        }
        let mut byte = 1u8;
        let mut vector = libc::iovec {
            iov_base: (&mut byte as *mut u8).cast(),
            iov_len: 1,
        };
        let mut control = [0usize; 8];
        let mut message: libc::msghdr = std::mem::zeroed();
        message.msg_iov = &mut vector;
        message.msg_iovlen = 1;
        message.msg_control = control.as_mut_ptr().cast();
        message.msg_controllen = libc::CMSG_SPACE(std::mem::size_of::<libc::c_int>() as _) as _;
        let header = libc::CMSG_FIRSTHDR(&message);
        (*header).cmsg_level = libc::SOL_SOCKET;
        (*header).cmsg_type = libc::SCM_RIGHTS;
        (*header).cmsg_len = libc::CMSG_LEN(std::mem::size_of::<libc::c_int>() as _) as _;
        libc::CMSG_DATA(header).cast::<libc::c_int>().write(pidfd);
        loop {
            let result = libc::sendmsg(socket, &message, libc::MSG_NOSIGNAL);
            if result == 1 {
                return Ok(());
            }
            let error = io::Error::last_os_error();
            if error.kind() != io::ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }
}
fn receive_capability(socket: libc::c_int) -> io::Result<OwnedFd> {
    unsafe {
        let mut byte = 0u8;
        let mut vector = libc::iovec {
            iov_base: (&mut byte as *mut u8).cast(),
            iov_len: 1,
        };
        let mut control = [0usize; 8];
        let mut message: libc::msghdr = std::mem::zeroed();
        message.msg_iov = &mut vector;
        message.msg_iovlen = 1;
        message.msg_control = control.as_mut_ptr().cast();
        message.msg_controllen = std::mem::size_of_val(&control);
        let result = libc::recvmsg(socket, &mut message, libc::MSG_CMSG_CLOEXEC);
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
        let mut received = Vec::new();
        let mut header = libc::CMSG_FIRSTHDR(&message);
        while !header.is_null() {
            if (*header).cmsg_level == libc::SOL_SOCKET && (*header).cmsg_type == libc::SCM_RIGHTS {
                let size = (*header)
                    .cmsg_len
                    .saturating_sub(libc::CMSG_LEN(0) as usize);
                for index in 0..size / std::mem::size_of::<libc::c_int>() {
                    received.push(OwnedFd::from_raw_fd(
                        libc::CMSG_DATA(header)
                            .cast::<libc::c_int>()
                            .add(index)
                            .read(),
                    ));
                }
            }
            header = libc::CMSG_NXTHDR(&message, header);
        }
        if result != 1
            || byte != 1
            || message.msg_flags & libc::MSG_CTRUNC != 0
            || received.len() != 1
        {
            return Err(io::Error::other("原进程监督能力交付不完整"));
        }
        Ok(received.pop().expect("已核验唯一 pidfd"))
    }
}
