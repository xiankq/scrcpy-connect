//! 独立执行监督器；真实命令是 VM 的孙进程，参数及输出含义由调用方解释。
#![allow(dead_code)]
mod protocol;
use protocol::{Event, Launch};
use std::{
    io::{self, Read},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{net::UnixStream, process::CommandExt},
    },
    process::{Command, Stdio},
};
#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}
unsafe extern "C" {
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    fn close(fd: i32) -> i32;
    fn poll(descriptors: *mut PollFd, count: usize, timeout: i32) -> i32;
    fn signal(signal: i32, handler: usize) -> usize;
    fn prctl(option: i32, ...) -> i32;
    fn getppid() -> i32;
}
fn run(control_fd: i32) -> io::Result<()> {
    // exec 后重置 SIGCHLD；不继承嵌入宿主可能设置的忽略处置。
    unsafe {
        signal(17, 0);
    }
    if control_fd < 3 || unsafe { fcntl(control_fd, 2, 1) } == -1 {
        return Err(io::Error::last_os_error());
    }
    let mut control = unsafe { UnixStream::from_raw_fd(control_fd) };
    let launch = Launch::decode(&protocol::read_frame(&mut control)?)?;
    let mut command = Command::new(&launch.executable);
    command
        .args(&launch.arguments)
        .envs(&launch.environment)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    let ack = launch.ack_fd;
    if ack.is_some_and(|fd| fd < 3 || fd == control_fd) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "无效回执描述符",
        ));
    }
    let supervisor = std::process::id() as i32;
    unsafe {
        command.pre_exec(move || {
            // 意外监督器死亡时至少终止目标；这不能替代目标 waitstatus 回执。
            if prctl(1, 9, 0, 0, 0) == -1 || getppid() != supervisor {
                return Err(io::Error::from_raw_os_error(125));
            }
            if let Some(fd) = ack {
                if fcntl(fd, 2, 0) == -1 {
                    return Err(io::Error::last_os_error());
                }
            }
            Ok(())
        });
    }
    let result = command.spawn();
    drop(command);
    if let Some(fd) = launch.ack_fd {
        unsafe {
            close(fd);
        }
    }
    let mut child = match result {
        Ok(child) => child,
        Err(error) => {
            Event::StartFailed(error.to_string()).write(&mut control)?;
            return Ok(());
        }
    };
    let mut disconnected = Event::Started(child.id()).write(&mut control).is_err();
    let mut stop = disconnected;
    let mut identity_lost = false;
    loop {
        // 本进程没有其它回收线程；wait 错误也不能遗弃还可能存活的命令。
        if !identity_lost {
            match child.try_wait() {
                Ok(Some(status)) => {
                    if !disconnected {
                        let _ = Event::Exited(status.code()).write(&mut control);
                    }
                    return Ok(());
                }
                Ok(None) => {}
                Err(error) => {
                    identity_lost = error.raw_os_error() == Some(10);
                    if !disconnected {
                        disconnected = Event::TerminationFailed(error.to_string())
                            .write(&mut control)
                            .is_err();
                    }
                }
            }
        }
        if stop && !identity_lost {
            if let Err(error) = child.kill() {
                if !disconnected {
                    disconnected = Event::TerminationFailed(error.to_string())
                        .write(&mut control)
                        .is_err();
                }
            }
            stop = disconnected;
        }
        if disconnected {
            std::thread::sleep(std::time::Duration::from_millis(10));
            continue;
        }
        let mut event = PollFd {
            fd: control.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        let ready = unsafe { poll(&mut event, 1, 10) };
        if ready < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            disconnected = true;
            stop = true;
            continue;
        }
        if ready > 0 {
            let mut messages = [0u8; 64];
            match control.read(&mut messages) {
                Ok(0) => {
                    disconnected = true;
                    stop = true;
                }
                Ok(size) => {
                    if messages[..size].contains(&protocol::STOP) {
                        stop = true;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(_) => {
                    disconnected = true;
                    stop = true;
                }
            }
        }
    }
}
fn main() {
    let mut arguments = std::env::args().skip(1);
    let fd = match (
        arguments.next().as_deref(),
        arguments.next(),
        arguments.next(),
    ) {
        (Some("--control-fd"), Some(value), None) => value.parse::<i32>().ok(),
        _ => None,
    };
    let Some(fd) = fd else {
        std::process::exit(2);
    };
    let result = run(fd);
    std::process::exit(if result.is_ok() { 0 } else { 1 });
}
