//! 使用精确进程 HANDLE 和继承白名单，ACK 不借用任何标准流。
use super::*;
use std::{
    collections::BTreeMap,
    os::windows::{
        ffi::OsStrExt,
        io::{AsRawHandle, FromRawHandle, OwnedHandle},
    },
    ptr,
};
use tokio::net::windows::named_pipe::{NamedPipeServer, ServerOptions};
use windows_sys::Win32::{Foundation::*, System::Threading::*};

pub(in crate::api) struct Process {
    handle: OwnedHandle,
    pid: u32,
    exited: Option<Option<i32>>,
}
impl Process {
    pub(in crate::api) fn id(&self) -> Option<u32> {
        Some(self.pid)
    }
    pub(in crate::api) fn terminate(&mut self) -> io::Result<()> {
        if self.exited.is_some() {
            return Ok(());
        }
        if unsafe { TerminateProcess(self.handle.as_raw_handle(), 1) } == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
    pub(in crate::api) async fn wait(&mut self) -> io::Result<Option<i32>> {
        if let Some(code) = self.exited {
            return Ok(code);
        }
        loop {
            match unsafe { WaitForSingleObject(self.handle.as_raw_handle(), 0) } {
                WAIT_OBJECT_0 => {
                    let mut code = 0;
                    if unsafe { GetExitCodeProcess(self.handle.as_raw_handle(), &mut code) } == 0 {
                        return Err(io::Error::last_os_error());
                    }
                    let code = Some(code as i32);
                    self.exited = Some(code);
                    return Ok(code);
                }
                WAIT_TIMEOUT => tokio::time::sleep(std::time::Duration::from_millis(10)).await,
                _ => return Err(io::Error::last_os_error()),
            }
        }
    }
}
impl Drop for Process {
    fn drop(&mut self) {
        // 仅异常路径兜底；正常 finished 只能在 wait 证实同一 HANDLE 退出后发布。
        if self.exited.is_none() {
            let _ = self.terminate();
        }
    }
}
struct Attributes {
    storage: Vec<usize>,
    initialized: bool,
}
impl Attributes {
    fn new(handles: &[HANDLE]) -> io::Result<Self> {
        let mut bytes = 0;
        unsafe {
            InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut bytes);
        }
        if bytes == 0 {
            return Err(io::Error::last_os_error());
        }
        let mut value = Self {
            storage: vec![0; bytes.div_ceil(std::mem::size_of::<usize>())],
            initialized: false,
        };
        if unsafe { InitializeProcThreadAttributeList(value.as_mut(), 1, 0, &mut bytes) } == 0 {
            return Err(io::Error::last_os_error());
        }
        value.initialized = true;
        if unsafe {
            UpdateProcThreadAttribute(
                value.as_mut(),
                0,
                PROC_THREAD_ATTRIBUTE_HANDLE_LIST as usize,
                handles.as_ptr().cast(),
                std::mem::size_of_val(handles),
                ptr::null_mut(),
                ptr::null(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(value)
    }
    fn as_mut(&mut self) -> LPPROC_THREAD_ATTRIBUTE_LIST {
        self.storage.as_mut_ptr().cast()
    }
}
impl Drop for Attributes {
    fn drop(&mut self) {
        if self.initialized {
            unsafe {
                DeleteProcThreadAttributeList(self.as_mut());
            }
        }
    }
}
async fn pipe(parent_reads: bool) -> io::Result<(NamedPipeServer, OwnedHandle)> {
    let name = format!(r"\\.\pipe\interop-adb-{}", uuid::Uuid::new_v4());
    let parent = ServerOptions::new()
        .access_inbound(parent_reads)
        .access_outbound(!parent_reads)
        .first_pipe_instance(true)
        .reject_remote_clients(true)
        .create(&name)?;
    let child = std::fs::OpenOptions::new()
        .read(!parent_reads)
        .write(parent_reads)
        .open(name)?;
    let mut inherited = ptr::null_mut();
    if unsafe {
        DuplicateHandle(
            GetCurrentProcess(),
            child.as_raw_handle(),
            GetCurrentProcess(),
            &mut inherited,
            0,
            1,
            DUPLICATE_SAME_ACCESS,
        )
    } == 0
    {
        return Err(io::Error::last_os_error());
    }
    let inherited = unsafe { OwnedHandle::from_raw_handle(inherited) };
    drop(child);
    parent.connect().await?;
    Ok((parent, inherited))
}
fn wide(value: impl AsRef<std::ffi::OsStr>) -> Vec<u16> {
    value.as_ref().encode_wide().chain(Some(0)).collect()
}
fn quote(value: &str) -> String {
    let mut quoted = String::from("\"");
    let mut slashes = 0;
    for ch in value.chars() {
        if ch == '\\' {
            slashes += 1;
            continue;
        }
        quoted.extend(std::iter::repeat_n(
            '\\',
            if ch == '"' { slashes * 2 + 1 } else { slashes },
        ));
        quoted.push(ch);
        slashes = 0;
    }
    quoted.extend(std::iter::repeat_n('\\', slashes * 2));
    quoted.push('"');
    quoted
}
fn environment_block(overrides: &HashMap<String, String>) -> Vec<u16> {
    // 保留继承环境的 UTF-16 原值，覆盖名称不区分大小写。
    let mut values = BTreeMap::new();
    for (key, value) in std::env::vars_os() {
        values.insert(
            key.to_string_lossy().to_uppercase(),
            (
                key.encode_wide().collect::<Vec<_>>(),
                value.encode_wide().collect::<Vec<_>>(),
            ),
        );
    }
    for (key, value) in overrides {
        values.insert(
            key.to_uppercase(),
            (key.encode_utf16().collect(), value.encode_utf16().collect()),
        );
    }
    let mut block = Vec::new();
    for (key, value) in values.into_values() {
        block.extend(key);
        block.push('=' as u16);
        block.extend(value);
        block.push(0);
    }
    if block.is_empty() {
        block.push(0);
    }
    block.push(0);
    block
}
pub(super) async fn spawn(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    ack: bool,
) -> io::Result<Spawned> {
    let (input, stdin) = pipe(false).await?;
    let (output, stdout) = pipe(true).await?;
    let (error, stderr) = pipe(true).await?;
    let ack = if ack { Some(pipe(true).await?) } else { None };
    let mut args = vec![executable.to_owned()];
    if let Some((_, child)) = &ack {
        let handle = child.as_raw_handle() as usize;
        // ADB 以整数传递 HANDLE，要求往返 32 位后保持相同内核对象值。
        if handle != handle as u32 as usize {
            return Err(io::Error::other("ACK HANDLE 超出 ADB 支持范围。"));
        }
        args.extend(["--reply-fd".into(), handle.to_string()]);
    }
    args.extend(arguments.iter().cloned());
    let mut command_line = wide(
        args.iter()
            .map(|arg| quote(arg))
            .collect::<Vec<_>>()
            .join(" "),
    );
    let executable = wide(executable);
    let environment = environment_block(environment);
    let mut handles = vec![
        stdin.as_raw_handle(),
        stdout.as_raw_handle(),
        stderr.as_raw_handle(),
    ];
    if let Some((_, child)) = &ack {
        handles.push(child.as_raw_handle());
    }
    let mut attributes = Attributes::new(&handles)?;
    let mut startup = STARTUPINFOEXW::default();
    startup.StartupInfo.cb = std::mem::size_of::<STARTUPINFOEXW>() as u32;
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = stdin.as_raw_handle();
    startup.StartupInfo.hStdOutput = stdout.as_raw_handle();
    startup.StartupInfo.hStdError = stderr.as_raw_handle();
    startup.lpAttributeList = attributes.as_mut();
    let mut created = PROCESS_INFORMATION::default();
    if unsafe {
        CreateProcessW(
            executable.as_ptr(),
            command_line.as_mut_ptr(),
            ptr::null(),
            ptr::null(),
            1,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
            environment.as_ptr().cast(),
            ptr::null(),
            &startup.StartupInfo,
            &mut created,
        )
    } == 0
    {
        return Err(io::Error::last_os_error());
    }
    // 从此处开始不能再失败，原进程 HANDLE 必须交给监督 worker 等待。
    let handle = unsafe { OwnedHandle::from_raw_handle(created.hProcess) };
    drop(unsafe { OwnedHandle::from_raw_handle(created.hThread) });
    drop((stdin, stdout, stderr));
    let ack = ack.map(|(parent, child)| {
        drop(child);
        Box::pin(parent) as Reader
    });
    Ok(Spawned {
        process: Process {
            handle,
            pid: created.dwProcessId,
            exited: None,
        },
        input: Box::pin(input),
        output: Box::pin(output),
        error: Box::pin(error),
        ack,
    })
}
