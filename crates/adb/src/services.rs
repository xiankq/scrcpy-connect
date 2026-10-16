use crate::{Client, Error, OperationOptions, Result, error::bounded};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RemoteSocket {
    Tcp(std::num::NonZeroU16),
    LocalAbstract(String),
    LocalFilesystem(String),
    LocalReserved(String),
    Jdwp(std::num::NonZeroU32),
    Vsock { cid: u32, port: u32 },
}
impl RemoteSocket {
    fn service(&self) -> Result<String> {
        let service = match self {
            Self::Tcp(port) => format!("tcp:{port}"),
            Self::Jdwp(pid) => format!("jdwp:{pid}"),
            Self::Vsock { cid, port } => format!("vsock:{cid}:{port}"),
            Self::LocalAbstract(name) | Self::LocalFilesystem(name) | Self::LocalReserved(name) => {
                if name.is_empty() || name.contains('\0') {
                    return Err(Error::InvalidArgument("invalid local socket name"));
                }
                let prefix = match self {
                    Self::LocalAbstract(_) => "localabstract",
                    Self::LocalFilesystem(_) => "localfilesystem",
                    _ => "localreserved",
                };
                format!("{prefix}:{name}")
            }
        };
        Ok(service)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RebootTarget {
    System,
    Recovery,
    Bootloader,
    Fastboot,
    Sideload,
}

fn abb_service(prefix: &[u8], arguments: &[&str]) -> Result<Vec<u8>> {
    if arguments.is_empty() {
        return Err(Error::InvalidArgument("Binder bridge requires a command"));
    }
    let mut service = prefix.to_vec();
    for (index, argument) in arguments.iter().enumerate() {
        if argument.contains('\0') {
            return Err(Error::InvalidArgument("Binder argument contains NUL"));
        }
        if index != 0 {
            service.push(0);
        }
        service.extend_from_slice(argument.as_bytes());
    }
    Ok(service)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellOutput {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    /// None on legacy shell, whose protocol carries no exit status.
    pub exit_code: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellMode {
    Raw,
    Pty,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShellEvent {
    Stdout(Vec<u8>),
    Stderr(Vec<u8>),
    Exit(u8),
}

/// Interactive shell_v2. `next_event` retains partial packets when its future is
/// dropped, so an input event may interrupt a pending read without losing bytes.
pub struct ShellSession {
    stream: crate::AdbStream,
    mode: ShellMode,
    max_packet: usize,
    header: [u8; 5],
    header_read: usize,
    payload: Vec<u8>,
    payload_read: usize,
    exited: bool,
    stdin_closed: bool,
}

impl ShellSession {
    pub async fn next_event(&mut self) -> Result<Option<ShellEvent>> {
        if self.exited {
            return Ok(None);
        }
        while self.header_read < 5 {
            let count = self
                .stream
                .read(&mut self.header[self.header_read..])
                .await?;
            if count == 0 {
                return Err(Error::Protocol(
                    "shell_v2 closed without exit status".into(),
                ));
            }
            self.header_read += count;
        }
        let length =
            u32::from_le_bytes(self.header[1..].try_into().expect("shell header")) as usize;
        if length > self.max_packet {
            self.stream.close_now();
            return Err(Error::OutputLimit);
        }
        if !matches!(self.header[0], 1..=3) || (self.header[0] == 3 && length != 1) {
            self.stream.close_now();
            return Err(Error::Protocol("invalid shell_v2 event".into()));
        }
        self.payload.resize(length, 0);
        while self.payload_read < length {
            let count = self
                .stream
                .read(&mut self.payload[self.payload_read..])
                .await?;
            if count == 0 {
                self.stream.close_now();
                return Err(Error::Protocol("truncated shell_v2 event".into()));
            }
            self.payload_read += count;
        }
        let payload = std::mem::take(&mut self.payload);
        self.payload_read = 0;
        self.header_read = 0;
        Ok(Some(match self.header[0] {
            1 => ShellEvent::Stdout(payload),
            2 => ShellEvent::Stderr(payload),
            3 => {
                self.exited = true;
                ShellEvent::Exit(payload[0])
            }
            _ => unreachable!("validated channel"),
        }))
    }

    pub async fn write_stdin(&mut self, bytes: &[u8]) -> Result<()> {
        if self.stdin_closed || self.exited {
            return Err(Error::Closed);
        }
        for chunk in bytes.chunks(64 * 1024) {
            self.write_packet(0, chunk).await?;
        }
        Ok(())
    }

    pub async fn close_stdin(&mut self) -> Result<()> {
        if self.stdin_closed {
            return Ok(());
        }
        if self.exited {
            return Err(Error::Closed);
        }
        self.write_packet(4, &[]).await?;
        self.stdin_closed = true;
        Ok(())
    }

    pub async fn resize(&mut self, rows: u16, columns: u16) -> Result<()> {
        if self.mode != ShellMode::Pty || rows == 0 || columns == 0 {
            return Err(Error::InvalidArgument(
                "terminal resize requires a PTY and nonzero dimensions",
            ));
        }
        if self.exited {
            return Err(Error::Closed);
        }
        self.write_packet(5, format!("{rows}x{columns},0x0\0").as_bytes())
            .await
    }

    async fn write_packet(&mut self, channel: u8, payload: &[u8]) -> Result<()> {
        let mut packet = Vec::with_capacity(5 + payload.len());
        packet.push(channel);
        packet.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        packet.extend_from_slice(payload);
        self.stream.write_all(&packet).await
    }

    pub async fn close(self) -> Result<()> {
        self.stream.close().await
    }
}

impl Client {
    /// Execute Android's cmd utility with individually quoted arguments.
    pub async fn cmd(
        &self,
        arguments: &[&str],
        max_output: usize,
        options: OperationOptions,
    ) -> Result<ShellOutput> {
        if !self.info().features.contains("cmd") {
            return Err(Error::Unsupported("cmd"));
        }
        let mut command = String::from("cmd");
        for argument in arguments {
            if argument.contains('\0') {
                return Err(Error::InvalidArgument("command argument contains NUL"));
            }
            command.push(' ');
            command.push('\'');
            command.push_str(&argument.replace('\'', "'\\''"));
            command.push('\'');
        }
        self.shell(&command, max_output, options).await
    }

    /// Android Binder bridge, using NUL-separated argv with shell_v2 events.
    pub async fn abb(
        &self,
        arguments: &[&str],
        max_packet: usize,
        options: OperationOptions,
    ) -> Result<ShellSession> {
        if !self.info().features.contains("abb") {
            return Err(Error::Unsupported("abb"));
        }
        if max_packet == 0 || max_packet > 1024 * 1024 {
            return Err(Error::InvalidArgument(
                "shell event limit must be between 1 byte and 1 MiB",
            ));
        }
        let service = abb_service(b"abb:", arguments)?;
        let stream = self.open_service(&service, options).await?;
        Ok(ShellSession {
            stream,
            mode: ShellMode::Raw,
            max_packet,
            header: [0; 5],
            header_read: 0,
            payload: Vec::new(),
            payload_read: 0,
            exited: false,
            stdin_closed: false,
        })
    }

    /// Raw Binder bridge byte stream, suitable for package install-write input.
    pub async fn abb_exec(
        &self,
        arguments: &[&str],
        options: OperationOptions,
    ) -> Result<crate::AdbStream> {
        if !self.info().features.contains("abb_exec") {
            return Err(Error::Unsupported("abb_exec"));
        }
        self.open_service(&abb_service(b"abb_exec:", arguments)?, options)
            .await
    }

    pub async fn connect_socket(
        &self,
        socket: &RemoteSocket,
        options: OperationOptions,
    ) -> Result<crate::AdbStream> {
        self.open(&socket.service()?, options).await
    }

    /// Successful OPEN acknowledges the reboot request, not completion of the reboot.
    pub async fn reboot(&self, target: RebootTarget, options: OperationOptions) -> Result<()> {
        let target = match target {
            RebootTarget::System => "",
            RebootTarget::Recovery => "recovery",
            RebootTarget::Bootloader => "bootloader",
            RebootTarget::Fastboot => "fastboot",
            RebootTarget::Sideload => "sideload",
        };
        let _stream = self.open(&format!("reboot:{target}"), options).await?;
        Ok(())
    }
    pub async fn shell_session(
        &self,
        command: &str,
        mode: ShellMode,
        max_packet: usize,
        options: OperationOptions,
    ) -> Result<ShellSession> {
        if !self.info().features.contains("shell_v2") {
            return Err(Error::Unsupported("shell_v2"));
        }
        if max_packet == 0 || max_packet > 1024 * 1024 {
            return Err(Error::InvalidArgument(
                "shell event limit must be between 1 byte and 1 MiB",
            ));
        }
        let mode_name = match mode {
            ShellMode::Raw => "raw",
            ShellMode::Pty => "pty",
        };
        let stream = self
            .open(&format!("shell,v2,{mode_name}:{command}"), options)
            .await?;
        Ok(ShellSession {
            stream,
            mode,
            max_packet,
            header: [0; 5],
            header_read: 0,
            payload: Vec::new(),
            payload_read: 0,
            exited: false,
            stdin_closed: false,
        })
    }
    /// Executes an explicitly supplied Android shell program. Shell quoting is the caller's responsibility.
    /// Output is bounded across stdout and stderr. Binary output is preserved.
    pub async fn shell(
        &self,
        command: &str,
        max_output: usize,
        options: OperationOptions,
    ) -> Result<ShellOutput> {
        bounded(options.timeout, &options.cancellation, async {
            let v2 = self.info().features.contains("shell_v2");
            let service = format!("{}{}", if v2 { "shell,v2,raw:" } else { "shell:" }, command);
            let mut stream = self.open(&service, options.clone()).await?;
            let mut output = ShellOutput {
                stdout: Vec::new(),
                stderr: Vec::new(),
                exit_code: None,
            };
            if v2 {
                loop {
                    let mut header = [0; 5];
                    if stream.read(&mut header[..1]).await? == 0 {
                        break;
                    }
                    stream.read_exact(&mut header[1..]).await?;
                    let length =
                        u32::from_le_bytes(header[1..].try_into().expect("shell header")) as usize;
                    match header[0] {
                        1 | 2 => {
                            let total = output
                                .stdout
                                .len()
                                .checked_add(output.stderr.len())
                                .and_then(|n| n.checked_add(length))
                                .ok_or(Error::OutputLimit)?;
                            if total > max_output {
                                return Err(Error::OutputLimit);
                            }
                            let destination = if header[0] == 1 {
                                &mut output.stdout
                            } else {
                                &mut output.stderr
                            };
                            let old = destination.len();
                            destination.resize(old + length, 0);
                            stream.read_exact(&mut destination[old..]).await?;
                        }
                        3 => {
                            if length != 1 {
                                return Err(Error::Protocol(
                                    "shell_v2 exit payload must contain one byte".into(),
                                ));
                            }
                            let mut status = [0];
                            stream.read_exact(&mut status).await?;
                            output.exit_code = Some(status[0] as u32);
                            break;
                        }
                        _ => {
                            return Err(Error::Protocol(
                                "unexpected shell_v2 output channel".into(),
                            ));
                        }
                    }
                }
                if output.exit_code.is_none() {
                    return Err(Error::Protocol(
                        "shell_v2 closed without exit status".into(),
                    ));
                }
            } else {
                let mut buffer = [0; 16 * 1024];
                loop {
                    let count = stream.read(&mut buffer).await?;
                    if count == 0 {
                        break;
                    }
                    if count > max_output.saturating_sub(output.stdout.len()) {
                        return Err(Error::OutputLimit);
                    }
                    output.stdout.extend_from_slice(&buffer[..count]);
                }
            }
            Ok(output)
        })
        .await
    }

    /// Open adbd's exec byte stream. Prefer shell_session(Raw) when stdin,
    /// stderr and exit status need explicit framing; the invoked program may
    /// itself choose interactive terminal behavior.
    pub async fn exec(&self, command: &str, options: OperationOptions) -> Result<crate::AdbStream> {
        self.open(&format!("exec:{command}"), options).await
    }

    pub async fn sync(&self, options: OperationOptions) -> Result<crate::sync::Sync> {
        Ok(crate::sync::Sync::new(
            self.open("sync:", options.clone()).await?,
            options,
            self.info().features.clone(),
        ))
    }
}
