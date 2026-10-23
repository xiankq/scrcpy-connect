//! Independent mobile ADB API. Pull-based typed events bound the Dart boundary
//! to one 64 KiB packet. Files stay on the host filesystem, outside command JSON.
use interop_adb::{
    Client, ConnectOptions, Identity, OperationOptions, ShellEvent, ShellMode, TlsPolicy,
};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};
use tokio::sync::{Mutex as AsyncMutex, mpsc};
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub struct AdbDeviceInfo {
    pub id: String,
    pub serial: String,
    pub state: String,
    pub features: Vec<String>,
}
pub struct AdbEvent {
    pub kind: String,
    pub bytes: Vec<u8>,
    pub exit_code: Option<u32>,
    pub transferred: u64,
    pub done: bool,
}
pub struct AdbServiceEvent {
    /// stdout, stderr, exit, or transfer. Legacy shell has no exit_code.
    pub kind: String,
    pub bytes: Vec<u8>,
    pub exit_code: Option<u32>,
    pub transferred: u64,
    pub done: bool,
    pub facts: Option<AdbServiceFacts>,
}
struct Connection {
    client: Client,
    serial: String,
}

pub struct AdbConnectionFacts {
    pub official_server: bool,
    pub transport_id: Option<u64>,
    pub protocol_version: Option<u32>,
    pub max_payload: Option<u32>,
    pub burst_mode: Option<bool>,
    pub closed: bool,
    pub features: Vec<String>,
}
pub struct AdbFileMetadata {
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
}
pub struct AdbDirectoryEntry {
    pub name: Vec<u8>,
    pub metadata: AdbFileMetadata,
}
pub struct AdbReverseMapping {
    pub serial: String,
    pub device_service: String,
    pub host_service: String,
}
pub struct AdbServiceFacts {
    pub metadata: Option<AdbFileMetadata>,
    pub entries: Vec<AdbDirectoryEntry>,
    pub pids: Vec<u32>,
    pub mappings: Vec<AdbReverseMapping>,
    pub device_service: Option<String>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbServiceKind {
    Raw,
    Exec,
    ShellRaw,
    ShellPty,
    Abb,
    AbbExec,
    Cmd,
    Response,
    Reboot,
    TcpIp,
    Usb,
    Jdwp,
    TrackJdwp,
}
/// `service` is the raw name, command, reboot target, or TCP port according to
/// kind. Binder/cmd use arguments; all other kinds reject unused arguments.
pub struct AdbServiceRequest {
    pub kind: AdbServiceKind,
    pub service: String,
    pub arguments: Vec<String>,
    pub max_output: u32,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbSyncKind {
    Stat,
    Lstat,
    List,
    Pull,
    Push,
    PullFile,
    PushFile,
}
#[derive(Clone, Copy)]
pub enum AdbCompression {
    None,
    Brotli,
    Lz4,
    Zstd,
}
pub struct AdbSyncRequest {
    pub kind: AdbSyncKind,
    pub path: Vec<u8>,
    pub local_path: String,
    pub max_bytes: u64,
    pub max_entries: u32,
    pub permissions: u32,
    pub modified_seconds: u32,
    pub compression: AdbCompression,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbInputKind {
    Bytes,
    CloseStdin,
    Resize,
    Finish,
}
pub struct AdbInput {
    pub kind: AdbInputKind,
    pub bytes: Vec<u8>,
    pub rows: u16,
    pub columns: u16,
}
#[derive(Clone, Copy)]
pub enum AdbReverseKind {
    Forward,
    List,
    Remove,
    RemoveAll,
}
pub struct AdbReverseRequest {
    pub kind: AdbReverseKind,
    pub device_service: String,
    pub host_address: String,
    pub no_rebind: bool,
}
struct SessionCommand {
    input: AdbInput,
    reply: tokio::sync::oneshot::Sender<Result<(), String>>,
}
fn event(kind: &str, done: bool) -> AdbServiceEvent {
    AdbServiceEvent {
        kind: kind.into(),
        bytes: Vec::new(),
        exit_code: None,
        transferred: 0,
        done,
        facts: None,
    }
}
fn facts() -> AdbServiceFacts {
    AdbServiceFacts {
        metadata: None,
        entries: Vec::new(),
        pids: Vec::new(),
        mappings: Vec::new(),
        device_service: None,
    }
}
fn metadata(value: interop_adb::sync::FileStat) -> AdbFileMetadata {
    AdbFileMetadata {
        mode: value.mode,
        size: value.size,
        modified_seconds: value.modified_seconds,
    }
}

/// Desktop services always pass through an already owned official server.
/// Numeric loopback only: this API never opens an adbd transport or authenticates.
pub async fn adb_connect_server(
    server_address: String,
    serial: String,
    timeout_ms: u32,
) -> Result<AdbDeviceInfo, String> {
    if cfg!(any(target_os = "android", target_os = "ios")) {
        return Err("official_adb_server_is_desktop_only".into());
    }
    let address: std::net::SocketAddr = server_address
        .parse()
        .map_err(|_| "invalid_adb_server_address")?;
    if !address.ip().is_loopback() || address.port() == 0 {
        return Err("invalid_adb_server_address".into());
    }
    let client = Client::connect_server(
        address,
        &serial,
        options(timeout_ms, CancellationToken::new())?,
    )
    .await
    .map_err(|e| e.to_string())?;
    insert(client, serial)
}
pub fn adb_connection_facts(connection_id: String) -> Result<AdbConnectionFacts, String> {
    let client = device(&connection_id)?;
    let direct = !client.uses_server();
    Ok(AdbConnectionFacts {
        official_server: !direct,
        transport_id: client.server_transport_id(),
        protocol_version: direct.then_some(client.info().version),
        max_payload: direct.then_some(client.info().max_payload as u32),
        burst_mode: direct.then_some(client.burst_mode()),
        closed: client.is_closed(),
        features: client.info().features.iter().cloned().collect(),
    })
}
/// One bounded input (64 KiB) and one outstanding writer per operation. A write
/// acknowledgement means the backend accepted bytes, not remote execution.
pub async fn adb_write(operation_id: String, input: AdbInput) -> Result<(), String> {
    if input.bytes.len() > 65536 {
        return Err("adb_input_limit".into());
    }
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(&operation_id)
        .cloned()
        .ok_or("adb_operation_closed")?;
    let _writer = op
        .writer
        .try_lock()
        .map_err(|_| "adb_operation_has_a_writer")?;
    let sender = op
        .input
        .lock()
        .expect("adb input")
        .clone()
        .ok_or("adb_operation_has_no_input")?;
    let (reply, receive) = tokio::sync::oneshot::channel();
    let work = async {
        sender
            .send(SessionCommand { input, reply })
            .await
            .map_err(|_| "adb_operation_closed".to_owned())?;
        receive
            .await
            .map_err(|_| "adb_operation_closed".to_owned())?
    };
    tokio::select! { _=op.stop.cancelled()=>Err("adb_operation_cancelled".into()),
    result=tokio::time::timeout(Duration::from_secs(45),work)=>
        match result { Ok(result) => result, Err(_) => {
            op.stop.cancel(); Err("adb_write_timeout".into())
        }} }
}

async fn raw_session(
    stream: interop_adb::AdbStream,
    send: &Events,
    input: &mut mpsc::Receiver<SessionCommand>,
    stop: &CancellationToken,
) -> Result<(), String> {
    let (mut reader, mut writer) = stream.into_split();
    let reading = async {
        let mut bytes = vec![0; 65536];
        loop {
            let count = reader.read(&mut bytes).await.map_err(|e| e.to_string())?;
            let mut result = event(if count == 0 { "end" } else { "data" }, count == 0);
            result.bytes = bytes[..count].to_vec();
            if !send_event(send, Ok(result), stop).await || count == 0 {
                return Ok(());
            }
        }
    };
    let writing = async {
        while let Some(command) = input.recv().await {
            let result = if command.input.kind == AdbInputKind::Bytes {
                writer
                    .write_all(&command.input.bytes)
                    .await
                    .map_err(|e| e.to_string())
            } else {
                Err("adb_raw_service_has_no_half_close_or_terminal_control".into())
            };
            let failed = result.is_err();
            let _ = command.reply.send(result);
            if failed {
                return Err("adb_service_write_failed".into());
            }
        }
        Ok(())
    };
    tokio::select! { result=reading=>result, result=writing=>result }
}
async fn shell_session(
    shell: interop_adb::ShellSession,
    send: &Events,
    input: &mut mpsc::Receiver<SessionCommand>,
    stop: &CancellationToken,
) -> Result<(), String> {
    let (mut reader, mut writer) = shell.into_split();
    let reading = async {
        while let Some(next) = reader.next_event().await.map_err(|e| e.to_string())? {
            let result = match next {
                ShellEvent::Stdout(bytes) => AdbServiceEvent {
                    bytes,
                    ..event("stdout", false)
                },
                ShellEvent::Stderr(bytes) => AdbServiceEvent {
                    bytes,
                    ..event("stderr", false)
                },
                ShellEvent::Exit(code) => AdbServiceEvent {
                    exit_code: Some(code.into()),
                    ..event("exit", true)
                },
            };
            if !send_event(send, Ok(result), stop).await {
                break;
            }
        }
        Ok(())
    };
    let writing = async {
        while let Some(command) = input.recv().await {
            let result = match command.input.kind {
                AdbInputKind::Bytes => writer.write_stdin(&command.input.bytes).await,
                AdbInputKind::CloseStdin => writer.close_stdin().await,
                AdbInputKind::Resize => {
                    writer
                        .resize(command.input.rows, command.input.columns)
                        .await
                }
                AdbInputKind::Finish => Err(interop_adb::Error::InvalidArgument(
                    "use closeStdin for a shell",
                )),
            }
            .map_err(|e| e.to_string());
            let failed = result.is_err();
            let _ = command.reply.send(result);
            if failed {
                return Err("adb_shell_write_failed".into());
            }
        }
        Ok(())
    };
    tokio::select! { result=reading=>result, result=writing=>result }
}

pub async fn adb_service(
    connection_id: String,
    request: AdbServiceRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    if request.max_output == 0 || request.max_output > 16 * 1024 * 1024 {
        return Err("invalid_adb_output_limit".into());
    }
    if !matches!(
        request.kind,
        AdbServiceKind::Abb | AdbServiceKind::AbbExec | AdbServiceKind::Cmd
    ) && !request.arguments.is_empty()
    {
        return Err("unexpected_adb_arguments".into());
    }
    let client = device(&connection_id)?;
    let (id, op, send) = operation(connection_id)?;
    let (input_send, mut input) = mpsc::channel(1);
    *op.input.lock().expect("adb input") = Some(input_send);
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            let kind = request.kind;
            let command = &request.service;
            let argv: Vec<&str> = request.arguments.iter().map(String::as_str).collect();
            match kind {
                AdbServiceKind::Raw | AdbServiceKind::Exec | AdbServiceKind::AbbExec => {
                    let stream = match kind {
                        AdbServiceKind::Raw => client.open(command, options.clone()).await,
                        AdbServiceKind::Exec => client.exec(command, options.clone()).await,
                        _ => client.abb_exec(&argv, options.clone()).await,
                    }
                    .map_err(|e| e.to_string())?;
                    raw_session(stream, &send, &mut input, &op.stop).await?;
                }
                AdbServiceKind::ShellRaw | AdbServiceKind::ShellPty | AdbServiceKind::Abb => {
                    let shell = if kind == AdbServiceKind::Abb {
                        client
                            .abb(&argv, request.max_output as usize, options.clone())
                            .await
                    } else {
                        client
                            .shell_session(
                                command,
                                if kind == AdbServiceKind::ShellPty {
                                    ShellMode::Pty
                                } else {
                                    ShellMode::Raw
                                },
                                request.max_output as usize,
                                options.clone(),
                            )
                            .await
                    }
                    .map_err(|e| e.to_string())?;
                    shell_session(shell, &send, &mut input, &op.stop).await?;
                }
                AdbServiceKind::Cmd => {
                    let result = client
                        .cmd(&argv, request.max_output as usize, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    for (kind, bytes) in [("stdout", result.stdout), ("stderr", result.stderr)] {
                        for chunk in bytes.chunks(65536) {
                            if !send_event(
                                &send,
                                Ok(AdbServiceEvent {
                                    bytes: chunk.to_vec(),
                                    ..event(kind, false)
                                }),
                                &op.stop,
                            )
                            .await
                            {
                                return Ok(());
                            }
                        }
                    }
                    send_event(
                        &send,
                        Ok(AdbServiceEvent {
                            exit_code: result.exit_code,
                            ..event("exit", true)
                        }),
                        &op.stop,
                    )
                    .await;
                }
                AdbServiceKind::Response | AdbServiceKind::TcpIp | AdbServiceKind::Usb => {
                    let bytes = match kind {
                        AdbServiceKind::TcpIp => {
                            client
                                .tcpip(
                                    command.parse().map_err(|_| "invalid_adb_tcp_port")?,
                                    options.clone(),
                                )
                                .await
                        }
                        AdbServiceKind::Usb => client.usb(options.clone()).await,
                        _ => {
                            client
                                .service_response(
                                    command,
                                    request.max_output as usize,
                                    options.clone(),
                                )
                                .await
                        }
                    }
                    .map_err(|e| e.to_string())?;
                    let chunks = bytes.chunks(65536).collect::<Vec<_>>();
                    if chunks.is_empty() {
                        send_event(&send, Ok(event("response", true)), &op.stop).await;
                    }
                    for (index, chunk) in chunks.iter().enumerate() {
                        send_event(
                            &send,
                            Ok(AdbServiceEvent {
                                bytes: chunk.to_vec(),
                                ..event("response", index + 1 == chunks.len())
                            }),
                            &op.stop,
                        )
                        .await;
                    }
                }
                AdbServiceKind::Reboot => {
                    let target = match command.as_str() {
                        "" => interop_adb::RebootTarget::System,
                        "recovery" => interop_adb::RebootTarget::Recovery,
                        "bootloader" => interop_adb::RebootTarget::Bootloader,
                        "fastboot" => interop_adb::RebootTarget::Fastboot,
                        "sideload" => interop_adb::RebootTarget::Sideload,
                        _ => return Err("invalid_adb_reboot_target".into()),
                    };
                    client
                        .reboot(target, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    send_event(&send, Ok(event("done", true)), &op.stop).await;
                }
                AdbServiceKind::Jdwp | AdbServiceKind::TrackJdwp => {
                    let mut tracker = client
                        .track_jdwp(request.max_output as usize, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    while let Some(pids) = tracker.next_event().await.map_err(|e| e.to_string())? {
                        let mut result = event("jdwp", kind == AdbServiceKind::Jdwp);
                        let mut value = facts();
                        value.pids = pids.into_iter().map(|pid| pid.get()).collect();
                        result.facts = Some(value);
                        if !send_event(&send, Ok(result), &op.stop).await
                            || kind == AdbServiceKind::Jdwp
                        {
                            break;
                        }
                    }
                }
            }
            Ok::<(), String>(())
        };
        let result = tokio::select! { _=op.stop.cancelled()=>return,
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_service_timeout".into())) };
        if let Err(error) = result {
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}

fn compression(value: AdbCompression) -> interop_adb::sync::Compression {
    match value {
        AdbCompression::None => interop_adb::sync::Compression::None,
        AdbCompression::Brotli => interop_adb::sync::Compression::Brotli,
        AdbCompression::Lz4 => interop_adb::sync::Compression::Lz4,
        AdbCompression::Zstd => interop_adb::sync::Compression::Zstd,
    }
}
/// SYNC protocol execution only. Paths are raw bytes, listings and queues are
/// bounded; conflict decisions, directory recursion and durable task state do
/// not belong to this API.
pub async fn adb_sync(
    connection_id: String,
    request: AdbSyncRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    if request.max_entries == 0 || request.max_entries > 100_000 || request.permissions > 0o777 {
        return Err("invalid_adb_sync_limits".into());
    }
    let client = device(&connection_id)?;
    let path = interop_adb::sync::RemotePath::new(&request.path).map_err(|e| e.to_string())?;
    let (id, op, send) = operation(connection_id)?;
    let (input_send, mut input) = mpsc::channel(1);
    *op.input.lock().expect("adb input") = Some(input_send);
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let _completion = completion;
        let mut created = false;
        let work = async {
            let mut sync = client
                .sync(options.clone())
                .await
                .map_err(|e| e.to_string())?;
            let mut result = event("sync", true);
            let mut value = facts();
            match request.kind {
                AdbSyncKind::Stat | AdbSyncKind::Lstat => {
                    let stat = if request.kind == AdbSyncKind::Stat {
                        sync.stat(&path).await
                    } else {
                        sync.lstat(&path).await
                    };
                    value.metadata = Some(metadata(stat.map_err(|e| e.to_string())?));
                    result.facts = Some(value);
                }
                AdbSyncKind::List => {
                    let entries = sync
                        .list(&path, request.max_entries as usize)
                        .await
                        .map_err(|e| e.to_string())?;
                    // Send bounded pages without making the directory a Dart JSON blob.
                    for page in entries.chunks(64) {
                        let mut value = facts();
                        value.entries = page
                            .iter()
                            .map(|entry| AdbDirectoryEntry {
                                name: entry.name.clone(),
                                metadata: AdbFileMetadata {
                                    mode: entry.stat.mode,
                                    size: entry.stat.size,
                                    modified_seconds: entry.stat.modified_seconds,
                                },
                            })
                            .collect();
                        if !send_event(
                            &send,
                            Ok(AdbServiceEvent {
                                facts: Some(value),
                                ..event("entries", false)
                            }),
                            &op.stop,
                        )
                        .await
                        {
                            return Ok(());
                        }
                    }
                }
                AdbSyncKind::PullFile | AdbSyncKind::PushFile => {
                    result.transferred = if request.kind == AdbSyncKind::PushFile {
                        let mut file = tokio::fs::File::open(&request.local_path)
                            .await
                            .map_err(|e| e.to_string())?;
                        sync.push_compressed(
                            &path,
                            &mut file,
                            request.permissions,
                            request.modified_seconds,
                            request.max_bytes,
                            compression(request.compression),
                        )
                        .await
                        .map_err(|e| e.to_string())?
                    } else {
                        let mut file = tokio::fs::OpenOptions::new()
                            .write(true)
                            .create_new(true)
                            .open(&request.local_path)
                            .await
                            .map_err(|e| e.to_string())?;
                        created = true;
                        let count = sync
                            .pull_compressed(
                                &path,
                                &mut file,
                                request.max_bytes,
                                compression(request.compression),
                            )
                            .await
                            .map_err(|e| e.to_string())?;
                        file.flush().await.map_err(|e| e.to_string())?;
                        count
                    };
                }
                AdbSyncKind::Push => {
                    let (mut reader, mut writer) = tokio::io::duplex(65536);
                    let transfer = async {
                        sync.push_compressed(
                            &path,
                            &mut reader,
                            request.permissions,
                            request.modified_seconds,
                            request.max_bytes,
                            compression(request.compression),
                        )
                        .await
                        .map_err(|e| e.to_string())
                    };
                    let feeding = async {
                        while let Some(command) = input.recv().await {
                            let finished = command.input.kind == AdbInputKind::Finish;
                            let result = match command.input.kind {
                                AdbInputKind::Bytes => writer
                                    .write_all(&command.input.bytes)
                                    .await
                                    .map_err(|e| e.to_string()),
                                AdbInputKind::Finish => {
                                    writer.shutdown().await.map_err(|e| e.to_string())
                                }
                                _ => Err("invalid_sync_input_control".into()),
                            };
                            let failed = result.is_err();
                            let _ = command.reply.send(result);
                            if failed {
                                return Err("adb_sync_input_failed".to_owned());
                            }
                            if finished {
                                return Ok(());
                            }
                        }
                        Err("adb_sync_input_closed_without_finish".into())
                    };
                    result.transferred = tokio::try_join!(transfer, feeding)?.0;
                }
                AdbSyncKind::Pull => {
                    let (mut reader, mut writer) = tokio::io::duplex(65536);
                    let transfer = async {
                        let count = sync
                            .pull_compressed(
                                &path,
                                &mut writer,
                                request.max_bytes,
                                compression(request.compression),
                            )
                            .await
                            .map_err(|e| e.to_string())?;
                        writer.shutdown().await.map_err(|e| e.to_string())?;
                        Ok::<_, String>(count)
                    };
                    let draining = async {
                        let mut bytes = vec![0; 65536];
                        loop {
                            let count = reader.read(&mut bytes).await.map_err(|e| e.to_string())?;
                            if count == 0 {
                                break;
                            }
                            if !send_event(
                                &send,
                                Ok(AdbServiceEvent {
                                    bytes: bytes[..count].to_vec(),
                                    ..event("data", false)
                                }),
                                &op.stop,
                            )
                            .await
                            {
                                return Err("adb_sync_reader_closed".into());
                            }
                        }
                        Ok::<_, String>(())
                    };
                    result.transferred = tokio::try_join!(transfer, draining)?.0;
                }
            }
            send_event(&send, Ok(result), &op.stop).await;
            Ok::<(), String>(())
        };
        let result = tokio::select! {_=op.stop.cancelled()=>Err("adb_sync_cancelled".into()),
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_sync_timeout".into()))};
        if let Err(error) = result {
            if created {
                let _ = tokio::fs::remove_file(&request.local_path).await;
            }
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}
fn reverse_socket(service: &str) -> Result<interop_adb::ReverseSocket, String> {
    let (kind, value) = service.split_once(':').ok_or("invalid_reverse_socket")?;
    match kind {
        "tcp" => Ok(interop_adb::ReverseSocket::Tcp(
            value.parse().map_err(|_| "invalid_reverse_port")?,
        )),
        "localabstract" => Ok(interop_adb::ReverseSocket::LocalAbstract(value.into())),
        "localfilesystem" => Ok(interop_adb::ReverseSocket::LocalFilesystem(value.into())),
        _ => Err("unsupported_reverse_socket".into()),
    }
}
fn reverse_service(socket: interop_adb::ReverseSocket) -> String {
    match socket {
        interop_adb::ReverseSocket::Tcp(port) => format!("tcp:{port}"),
        interop_adb::ReverseSocket::LocalAbstract(name) => format!("localabstract:{name}"),
        interop_adb::ReverseSocket::LocalFilesystem(name) => format!("localfilesystem:{name}"),
    }
}
pub async fn adb_reverse(
    connection_id: String,
    request: AdbReverseRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let client = device(&connection_id)?;
    let _ = options(timeout_ms, CancellationToken::new())?;
    let (id, op, send) = operation(connection_id)?;
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            let mut value = facts();
            match request.kind {
                AdbReverseKind::Forward => {
                    let destination = request
                        .host_address
                        .parse()
                        .map_err(|_| "invalid_reverse_destination")?;
                    let binding = client
                        .reverse_forward(
                            &reverse_socket(&request.device_service)?,
                            destination,
                            request.no_rebind,
                            options.clone(),
                        )
                        .await
                        .map_err(|e| e.to_string())?;
                    value.device_service = Some(reverse_service(binding.device));
                }
                AdbReverseKind::List => {
                    value.mappings = client
                        .reverse_list(options.clone())
                        .await
                        .map_err(|e| e.to_string())?
                        .into_iter()
                        .map(|m| AdbReverseMapping {
                            serial: m.serial,
                            device_service: m.device_service,
                            host_service: m.host_service,
                        })
                        .collect();
                }
                AdbReverseKind::Remove => client
                    .reverse_remove(&reverse_socket(&request.device_service)?, options.clone())
                    .await
                    .map_err(|e| e.to_string())?,
                AdbReverseKind::RemoveAll => client
                    .reverse_remove_all(options.clone())
                    .await
                    .map_err(|e| e.to_string())?,
            }
            send_event(
                &send,
                Ok(AdbServiceEvent {
                    facts: Some(value),
                    ..event("reverse", true)
                }),
                &op.stop,
            )
            .await;
            Ok::<(), String>(())
        };
        let result = tokio::select! {_=op.stop.cancelled()=>return,
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_reverse_timeout".into()))};
        if let Err(error) = result {
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}

struct Operation {
    connection: String,
    stop: CancellationToken,
    finished: CancellationToken,
    events: AsyncMutex<mpsc::Receiver<Result<AdbServiceEvent, String>>>,
    input: Mutex<Option<mpsc::Sender<SessionCommand>>>,
    writer: AsyncMutex<()>,
}
#[flutter_rust_bridge::frb(ignore)]
struct MobileAdbRegistry {
    connections: HashMap<String, Connection>,
    operations: HashMap<String, Arc<Operation>>,
}
static REGISTRY: OnceLock<Mutex<MobileAdbRegistry>> = OnceLock::new();
fn registry() -> &'static Mutex<MobileAdbRegistry> {
    REGISTRY.get_or_init(|| {
        Mutex::new(MobileAdbRegistry {
            connections: HashMap::new(),
            operations: HashMap::new(),
        })
    })
}
fn mobile() -> Result<(), String> {
    if cfg!(any(target_os = "android", target_os = "ios")) {
        Ok(())
    } else {
        Err("direct_mobile_adb_is_unavailable_on_desktop".into())
    }
}
fn options(timeout_ms: u32, stop: CancellationToken) -> Result<OperationOptions, String> {
    if timeout_ms == 0 || timeout_ms > 86_400_000 {
        return Err("invalid_adb_timeout".into());
    }
    Ok(OperationOptions {
        timeout: Duration::from_millis(timeout_ms.into()),
        cancellation: stop,
    })
}
async fn identity(path: &str) -> Result<Identity, String> {
    let pem = tokio::fs::read_to_string(path)
        .await
        .map_err(|e| format!("adb_identity: {e}"))?;
    Identity::from_pem(&pem).map_err(|e| e.to_string())
}
fn device(id: &str) -> Result<Client, String> {
    registry()
        .lock()
        .expect("adb registry")
        .connections
        .get(id)
        .map(|c| c.client.clone())
        .ok_or_else(|| "adb_connection_closed".into())
}
fn insert(client: Client, serial: String) -> Result<AdbDeviceInfo, String> {
    let mut state = registry().lock().expect("adb registry");
    if state.connections.len() >= 64 {
        client.close();
        return Err("adb_connection_limit".into());
    }
    let id = uuid::Uuid::new_v4().to_string();
    let info = AdbDeviceInfo {
        id: id.clone(),
        serial: serial.clone(),
        state: "device".into(),
        features: client.info().features.iter().cloned().collect(),
    };
    state.connections.insert(id, Connection { client, serial });
    Ok(info)
}
/// Uses the owning app's persisted identity, not a new per-call key.
pub async fn adb_connect_tcp(
    address: String,
    identity_path: String,
    require_tls: bool,
    authorize: bool,
    timeout_ms: u32,
) -> Result<AdbDeviceInfo, String> {
    mobile()?;
    let identity = identity(&identity_path).await?;
    let tls = interop_adb::wireless::TlsConfig::experimental_rustcrypto(&identity)
        .map_err(|e| e.to_string())?;
    let client = Client::connect_tcp(
        &address,
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            request_authorization: authorize,
            tls_policy: if require_tls {
                TlsPolicy::Required
            } else {
                TlsPolicy::Optional
            },
            operations: options(timeout_ms, CancellationToken::new())?,
            ..Default::default()
        },
    )
    .await
    .map_err(|e| e.to_string())?;
    insert(client, address)
}
/// Keep the platform-owned UsbDeviceConnection alive until disconnect.
pub async fn adb_connect_usb_fd(
    fd: i32,
    serial: String,
    identity_path: String,
    authorize: bool,
    timeout_ms: u32,
) -> Result<AdbDeviceInfo, String> {
    mobile()?;
    #[cfg(target_os = "android")]
    {
        use std::os::fd::BorrowedFd;
        let options = options(timeout_ms, CancellationToken::new())?;
        // The adapter duplicates this platform-owned descriptor synchronously.
        let transport = unsafe {
            interop_adb::usb::from_authorized_fd(BorrowedFd::borrow_raw(fd), options.clone()).await
        }
        .map_err(|e| e.to_string())?;
        let client = Client::connect_transport(
            transport,
            ConnectOptions {
                identity: Some(identity(&identity_path).await?),
                request_authorization: authorize,
                operations: options,
                ..Default::default()
            },
        )
        .await
        .map_err(|e| e.to_string())?;
        insert(client, serial)
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (fd, serial, identity_path, authorize, timeout_ms);
        Err("usb_requires_android_platform_authorization".into())
    }
}
pub async fn adb_pair(
    address: String,
    password: String,
    identity_path: String,
    timeout_ms: u32,
) -> Result<String, String> {
    mobile()?;
    let identity = identity(&identity_path).await?;
    let tls = interop_adb::wireless::TlsConfig::experimental_rustcrypto(&identity)
        .map_err(|e| e.to_string())?;
    let options = options(timeout_ms, CancellationToken::new())?;
    let stream = tokio::time::timeout(options.timeout, tokio::net::TcpStream::connect(address))
        .await
        .map_err(|_| "adb_pair_timeout".to_owned())?
        .map_err(|e| e.to_string())?;
    interop_adb::wireless::pair(stream, &password, &identity, &tls, "flutter_adb", &options)
        .await
        .map(|r| r.guid)
        .map_err(|e| e.to_string())
}
pub fn adb_devices() -> Vec<AdbDeviceInfo> {
    registry()
        .lock()
        .expect("adb registry")
        .connections
        .iter()
        .map(|(id, c)| AdbDeviceInfo {
            id: id.clone(),
            serial: c.serial.clone(),
            state: if c.client.is_closed() {
                "offline"
            } else {
                "device"
            }
            .into(),
            features: c.client.info().features.iter().cloned().collect(),
        })
        .collect()
}
pub async fn adb_disconnect(connection_id: String) {
    let operations = {
        let mut state = registry().lock().expect("adb registry");
        if let Some(connection) = state.connections.remove(&connection_id) {
            connection.client.close();
        }
        let operations = state
            .operations
            .iter()
            .filter(|(_, op)| op.connection == connection_id)
            .map(|(id, op)| (id.clone(), op.clone()))
            .collect::<Vec<_>>();
        for (id, op) in &operations {
            op.stop.cancel();
            state.operations.remove(id);
        }
        operations
    };
    let _ = tokio::time::timeout(Duration::from_secs(5), async {
        for (_, op) in operations {
            op.finished.cancelled().await;
        }
    })
    .await;
}
struct Completion(CancellationToken);
impl Drop for Completion {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
type Events = mpsc::Sender<Result<AdbServiceEvent, String>>;
fn operation(connection: String) -> Result<(String, Arc<Operation>, Events), String> {
    let mut state = registry().lock().expect("adb registry");
    if state.operations.len() >= 128 {
        return Err("adb_operation_limit".into());
    }
    let (send, events) = mpsc::channel(1);
    let op = Arc::new(Operation {
        connection,
        stop: CancellationToken::new(),
        finished: CancellationToken::new(),
        events: AsyncMutex::new(events),
        input: Mutex::new(None),
        writer: AsyncMutex::new(()),
    });
    let id = uuid::Uuid::new_v4().to_string();
    state.operations.insert(id.clone(), op.clone());
    // A reserved operation with no Dart reader must not permanently consume a
    // handle. An active reader holds events' mutex even while awaiting data.
    let orphan_id = id.clone();
    let weak = Arc::downgrade(&op);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(45)).await;
            let Some(operation) = weak.upgrade() else {
                break;
            };
            if operation.events.try_lock().is_ok() {
                adb_cancel(orphan_id).await;
                break;
            }
        }
    });
    Ok((id, op, send))
}
async fn send_event(
    send: &Events,
    event: Result<AdbServiceEvent, String>,
    stop: &CancellationToken,
) -> bool {
    tokio::select! { _=stop.cancelled()=>false,
    result=tokio::time::timeout(Duration::from_secs(45),send.send(event))=>matches!(result,Ok(Ok(()))), }
}
/// One consumer per operation. Awaiting the next event supplies backpressure.
pub async fn adb_service_next(operation_id: String) -> Result<Option<AdbServiceEvent>, String> {
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(&operation_id)
        .cloned()
        .ok_or("adb_operation_closed")?;
    let mut receiver = op
        .events
        .try_lock()
        .map_err(|_| "adb_operation_has_a_reader")?;
    let result = tokio::select! { _=op.stop.cancelled()=>return Err("adb_operation_cancelled".into()), event=receiver.recv()=>event };
    if !matches!(&result,Some(Ok(event))if !event.done) {
        registry()
            .lock()
            .expect("adb registry")
            .operations
            .remove(&operation_id);
    }
    result.transpose()
}
/// Existing noninteractive API; service consumers use the richer typed event.
pub async fn adb_next(operation_id: String) -> Result<Option<AdbEvent>, String> {
    Ok(adb_service_next(operation_id).await?.map(|event| AdbEvent {
        kind: event.kind,
        bytes: event.bytes,
        exit_code: event.exit_code,
        transferred: event.transferred,
        done: event.done,
    }))
}
pub async fn adb_cancel(operation_id: String) {
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .remove(&operation_id);
    if let Some(op) = op {
        op.stop.cancel();
        let _ = tokio::time::timeout(Duration::from_secs(5), op.finished.cancelled()).await;
    }
}
pub async fn adb_shell(
    connection_id: String,
    command: String,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    let client = device(&connection_id)?;
    let (id, op, send) = operation(connection_id)?;
    let options = match options(timeout_ms, op.stop.clone()) {
        Ok(o) => o,
        Err(e) => {
            adb_cancel(id).await;
            return Err(e);
        }
    };
    let stop = op.stop.clone();
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            if client.info().features.contains("shell_v2") {
                let mut shell = client
                    .shell_session(&command, ShellMode::Raw, 65536, options.clone())
                    .await
                    .map_err(|e| e.to_string())?;
                shell.close_stdin().await.map_err(|e| e.to_string())?;
                while let Some(event) = shell.next_event().await.map_err(|e| e.to_string())? {
                    let event = match event {
                        ShellEvent::Stdout(bytes) => AdbServiceEvent {
                            kind: "stdout".into(),
                            bytes,
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        },
                        ShellEvent::Stderr(bytes) => AdbServiceEvent {
                            kind: "stderr".into(),
                            bytes,
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        },
                        ShellEvent::Exit(code) => AdbServiceEvent {
                            kind: "exit".into(),
                            bytes: vec![],
                            exit_code: Some(code.into()),
                            transferred: 0,
                            done: true,
                            facts: None,
                        },
                    };
                    if !send_event(&send, Ok(event), &stop).await {
                        return Ok(());
                    }
                }
            } else {
                let mut stream = client
                    .open(&format!("shell:{command}"), options.clone())
                    .await
                    .map_err(|e| e.to_string())?;
                let mut bytes = vec![0; 65536];
                loop {
                    let count = stream.read(&mut bytes).await.map_err(|e| e.to_string())?;
                    if count == 0 {
                        break;
                    }
                    if !send_event(
                        &send,
                        Ok(AdbServiceEvent {
                            kind: "stdout".into(),
                            bytes: bytes[..count].to_vec(),
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        }),
                        &stop,
                    )
                    .await
                    {
                        return Ok(());
                    }
                }
                send_event(
                    &send,
                    Ok(AdbServiceEvent {
                        kind: "exit".into(),
                        bytes: vec![],
                        exit_code: None,
                        transferred: 0,
                        done: true,
                        facts: None,
                    }),
                    &stop,
                )
                .await;
            }
            Ok::<_, String>(())
        };
        let result = tokio::select! { _=stop.cancelled()=>return, result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_shell_timeout".into())) };
        if let Err(error) = result {
            send_event(&send, Err(error), &stop).await;
        }
    });
    Ok(id)
}
/// Pull creates a new local file, never overwrites, and removes partial failures.
#[allow(clippy::too_many_arguments)] // Flat generated FRB control arguments; payloads stay native.
pub async fn adb_transfer(
    connection_id: String,
    remote_path: String,
    local_path: String,
    push: bool,
    max_bytes: u64,
    permissions: u32,
    modified_seconds: u32,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    let client = device(&connection_id)?;
    let path =
        interop_adb::sync::RemotePath::new(remote_path.into_bytes()).map_err(|e| e.to_string())?;
    let (id, op, send) = operation(connection_id)?;
    let options = match options(timeout_ms, op.stop.clone()) {
        Ok(o) => o,
        Err(e) => {
            adb_cancel(id).await;
            return Err(e);
        }
    };
    let stop = op.stop.clone();
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let mut created = false;
        let work = async {
            let mut sync = client
                .sync(options.clone())
                .await
                .map_err(|e| e.to_string())?;
            if push {
                let mut input = tokio::fs::File::open(&local_path)
                    .await
                    .map_err(|e| e.to_string())?;
                sync.push(&path, &mut input, permissions, modified_seconds, max_bytes)
                    .await
                    .map_err(|e| e.to_string())
            } else {
                let mut output = tokio::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&local_path)
                    .await
                    .map_err(|e| e.to_string())?;
                created = true;
                sync.pull(&path, &mut output, max_bytes)
                    .await
                    .map_err(|e| e.to_string())
            }
        };
        let result = tokio::select! { _=stop.cancelled()=>Err("adb_transfer_cancelled".into()), result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_transfer_timeout".into())) };
        if result.is_err() && created {
            let _ = tokio::fs::remove_file(&local_path).await;
        }
        let event = result.map(|transferred| AdbServiceEvent {
            kind: "transfer".into(),
            bytes: vec![],
            exit_code: None,
            transferred,
            done: true,
            facts: None,
        });
        send_event(&send, event, &stop).await;
    });
    Ok(id)
}
pub async fn adb_close_all() {
    let operations = {
        let mut state = registry().lock().expect("adb registry");
        for (_, connection) in state.connections.drain() {
            connection.client.close();
        }
        let operations = std::mem::take(&mut state.operations);
        for op in operations.values() {
            op.stop.cancel();
        }
        operations
    };
    let _ = tokio::time::timeout(Duration::from_secs(5), async {
        for op in operations.values() {
            op.finished.cancelled().await;
        }
    })
    .await;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn cancellation_waits_for_worker_cleanup_before_releasing_its_handle() {
        let (id, op, _send) = operation("cleanup-fixture".into()).unwrap();
        let completion = Completion(op.finished.clone());
        let stop = op.stop.clone();
        let cleaned = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let worker_cleaned = cleaned.clone();
        tokio::spawn(async move {
            let _completion = completion;
            stop.cancelled().await;
            tokio::time::sleep(Duration::from_millis(10)).await;
            worker_cleaned.store(true, std::sync::atomic::Ordering::SeqCst);
        });
        adb_cancel(id.clone()).await;
        assert!(cleaned.load(std::sync::atomic::Ordering::SeqCst));
        assert!(!registry().lock().unwrap().operations.contains_key(&id));
        assert!(adb_next(id).await.is_err());
    }
    #[tokio::test]
    async fn input_has_one_writer_and_cancellation_wakes_pending_acknowledgement() {
        let (id, op, _events) = operation("bounded-input-fixture".into()).unwrap();
        let (send, mut receive) = mpsc::channel(1);
        *op.input.lock().unwrap() = Some(send);
        let completion = Completion(op.finished.clone());
        let stop = op.stop.clone();
        let (accepted, accepting) = tokio::sync::oneshot::channel();
        let worker = tokio::spawn(async move {
            let _completion = completion;
            let command = receive.recv().await.unwrap();
            accepted.send(()).unwrap();
            // Keep the first writer's acknowledgement pending.
            stop.cancelled().await;
            drop(command);
        });
        let writing = tokio::spawn(adb_write(
            id.clone(),
            AdbInput {
                kind: AdbInputKind::Bytes,
                bytes: vec![0xff; 65536],
                rows: 0,
                columns: 0,
            },
        ));
        accepting.await.unwrap();
        assert_eq!(
            adb_write(
                id.clone(),
                AdbInput {
                    kind: AdbInputKind::Bytes,
                    bytes: vec![1],
                    rows: 0,
                    columns: 0,
                }
            )
            .await
            .unwrap_err(),
            "adb_operation_has_a_writer"
        );
        assert_eq!(
            adb_write(
                id.clone(),
                AdbInput {
                    kind: AdbInputKind::Bytes,
                    bytes: vec![1; 65537],
                    rows: 0,
                    columns: 0,
                }
            )
            .await
            .unwrap_err(),
            "adb_input_limit"
        );
        adb_cancel(id.clone()).await;
        assert!(writing.await.unwrap().is_err());
        worker.await.unwrap();
        assert!(!registry().lock().unwrap().operations.contains_key(&id));
    }
}
