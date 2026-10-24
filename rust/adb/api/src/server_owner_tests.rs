//! 真实子进程、专用回执、原生 worker 和 socket 的所有权回归；不访问公共服务器。
use super::*;
use std::os::unix::fs::PermissionsExt;

struct Fixture {
    _directory: tempfile::TempDir,
    launch: AdbServerLaunchSpec,
    marker: std::path::PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let executable = directory.path().join("controlled-adb");
        std::fs::write(
            &executable,
            r##"#!/usr/bin/python3
import os,sys,socket,threading,time
args=sys.argv[1:]
ack=None
if args and args[0]=='--reply-fd':
 ack=int(args[1]); args=args[2:]
mode=args[0] if args else 'server'
if mode=='server':
 host,port=os.environ['FIXTURE_ENDPOINT'].rsplit(':',1)
 listener=socket.socket(); listener.bind((host,int(port))); listener.listen()
 if ack is not None:
  if os.environ.get('FIXTURE_DELAY_ACK'):time.sleep(60)
  os.write(ack,b'BAD' if os.environ.get('FIXTURE_BAD_ACK') else b'OK\n'); os.close(ack)
 def handle(peer):
  try:
   with peer:
    header=peer.recv(4)
    if not header:return
    size=int(header,16); request=b''
    while len(request)<size:request+=peer.recv(size-len(request))
    if request==b'host:die':os._exit(9)
    if request.startswith(b'host:tport:serial:'):
     if request.endswith(b':blocked'):
      open(os.environ['FIXTURE_MARKER'],'wb').write(b'socket-admitted')
      while peer.recv(1024):pass
      open(os.environ['FIXTURE_MARKER']+'.closed','wb').write(b'socket-closed')
     else:peer.sendall(b'OKAY'+(7).to_bytes(8,'little'))
    elif request.endswith(b':features'):peer.sendall(b'OKAY0000')
    elif request==b'host:version':peer.sendall(b'OKAY00040029')
  except OSError:pass
 while True:
  peer,_=listener.accept();threading.Thread(target=handle,args=(peer,),daemon=True).start()
elif mode=='echo':
 data=sys.stdin.buffer.read();sys.stdout.buffer.write(data);sys.stderr.buffer.write(b'error-bytes')
elif mode=='touch':
 open(os.environ['FIXTURE_MARKER'],'wb').write(b'issued')
elif mode=='stall':
 open(os.environ['FIXTURE_MARKER'],'wb').write(b'issued');time.sleep(3600)
elif mode=='flood':
 sys.stdout.buffer.write(b'x'*(2*1024*1024));sys.stdout.buffer.flush()
elif mode=='exit':sys.exit(7)
"##,
        )
        .unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = listener.local_addr().unwrap().to_string();
        drop(listener);
        let marker = directory.path().join("issued");
        let launch = AdbServerLaunchSpec {
            executable: executable.to_string_lossy().into_owned(),
            arguments: vec!["server".into()],
            environment: HashMap::from([
                ("FIXTURE_ENDPOINT".into(), endpoint.clone()),
                (
                    "FIXTURE_MARKER".into(),
                    marker.to_string_lossy().into_owned(),
                ),
            ]),
            endpoint,
        };
        Self {
            _directory: directory,
            launch,
            marker,
        }
    }
    async fn ready(&self) -> AdbServerInfo {
        let reserved = adb_server_create(self.launch.clone()).await.unwrap();
        adb_server_start(reserved.lease_id, 5000).await.unwrap()
    }
    fn command(&self, mode: &str, may_create_transport: bool) -> AdbServerCommandSpec {
        AdbServerCommandSpec {
            executable: self.launch.executable.clone(),
            arguments: vec![mode.into()],
            input: vec![],
            timeout_ms: 5000,
            may_create_transport,
            preparation: false,
        }
    }
}
async fn issued(path: &std::path::Path) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !path.exists() {
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn pending_commands_and_reserved_servers_cannot_start_after_close() {
    let fixture = Fixture::new();
    let server = adb_server_create(fixture.launch.clone()).await.unwrap();
    assert_eq!(
        adb_server_start(server.lease_id.clone(), 0)
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::InvalidArgument
    );
    let mut spec = fixture.command("touch", false);
    spec.preparation = true;
    let command = adb_server_command_create(server.lease_id.clone(), spec)
        .await
        .unwrap();
    adb_server_command_cancel(command.clone()).await.unwrap();
    assert!(adb_server_command_run(command.clone()).await.is_err());
    adb_server_command_close(command).await.unwrap();
    assert!(!fixture.marker.exists(), "预取消的命令不能实际 spawn");
    adb_server_close(server.lease_id.clone()).await.unwrap();
    assert_eq!(
        adb_server_start(server.lease_id, 5000)
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::StaleLease
    );
}

#[tokio::test]
async fn exact_ack_claim_and_connection_lifetime_are_independent_of_control_lease() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    assert_eq!(server.phase, AdbServerPhase::Ready);
    assert!(server.pid.is_some());
    assert!(
        adb_connect_server(fixture.launch.endpoint.clone(), "device".into(), 5000, None)
            .await
            .is_err(),
        "未标记握手不能绕过原生服务器归属"
    );
    let handshake = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let device = adb_connect_server(
        fixture.launch.endpoint.clone(),
        "device".into(),
        5000,
        Some(handshake.clone()),
    )
    .await
    .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    let client = super::device(&device.id).unwrap();
    let lifetime = admit_capture(&device.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    let facts = adb_connection_facts(device.id.clone()).unwrap();
    assert_eq!(facts.server_id.as_deref(), Some(server.server_id.as_str()));
    let claimed = adb_server_claim(server.lease_id.clone()).await.unwrap();
    assert_ne!(claimed.lease_id, server.lease_id);
    assert!(!lifetime.is_cancelled());
    assert!(!client.is_closed());
    adb_server_close(server.lease_id.clone()).await.unwrap();
    assert!(
        adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.lease_id == claimed.lease_id)
    );
    assert_eq!(
        adb_server_handshake_create(server.lease_id)
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::StaleLease
    );
    adb_server_close(claimed.lease_id).await.unwrap();
    assert!(lifetime.is_cancelled());
    assert!(client.is_closed());
    assert!(adb_connection_facts(device.id).is_err());
}

#[tokio::test]
async fn real_commands_preserve_stdin_and_bound_output_and_timeout() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let mut echo = fixture.command("echo", false);
    echo.input = vec![0, 0xff, b'\n', b' ', b'1'];
    let id = adb_server_command_create(server.lease_id.clone(), echo.clone())
        .await
        .unwrap();
    let result = adb_server_command_run(id.clone()).await.unwrap();
    assert_eq!(result.status, AdbServerCommandStatus::Exited);
    assert_eq!(result.exit_code, Some(0));
    assert_eq!(result.stdout, echo.input);
    assert_eq!(result.stderr, b"error-bytes");
    adb_server_command_confirm(id.clone()).await.unwrap();
    adb_server_command_close(id).await.unwrap();
    let id = adb_server_command_create(server.lease_id.clone(), fixture.command("flood", false))
        .await
        .unwrap();
    let result = adb_server_command_run(id.clone()).await.unwrap();
    assert_eq!(result.status, AdbServerCommandStatus::OutputLimit);
    assert!(result.stdout.len() + result.stderr.len() <= 1024 * 1024);
    adb_server_command_close(id).await.unwrap();
    let mut stalled = fixture.command("stall", false);
    stalled.timeout_ms = 100;
    let id = adb_server_command_create(server.lease_id.clone(), stalled)
        .await
        .unwrap();
    let result = adb_server_command_run(id.clone()).await.unwrap();
    assert_eq!(result.status, AdbServerCommandStatus::TimedOut);
    assert!(
        result.exit_code.is_none(),
        "Unix signal 终止不能伪造普通退出码"
    );
    adb_server_command_close(id).await.unwrap();
    adb_server_close(server.lease_id).await.unwrap();
}

#[tokio::test]
async fn dropped_waiter_and_claim_drain_actual_command_and_keep_transport_unknown() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let id = adb_server_command_create(server.lease_id.clone(), fixture.command("stall", true))
        .await
        .unwrap();
    let waiting = tokio::spawn(adb_server_command_run(id.clone()));
    issued(&fixture.marker).await;
    waiting.abort();
    let _ = waiting.await;
    let claimed = adb_server_claim(server.lease_id.clone()).await.unwrap();
    assert!(
        claimed.transport_state_unknown,
        "CLI 退出不能证明 server 内的 connect worker 已撤销"
    );
    assert_eq!(
        adb_server_command_create(claimed.lease_id.clone(), fixture.command("echo", false))
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::TransportStateUnknown
    );
    assert_eq!(
        adb_server_handshake_create(claimed.lease_id.clone())
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::TransportStateUnknown
    );
    adb_server_close(server.lease_id).await.unwrap();
    adb_server_close(claimed.lease_id).await.unwrap();
    assert!(!registry().lock().unwrap().server_commands.contains_key(&id));
}

#[tokio::test]
async fn unconfirmed_mutation_is_sticky_but_explicit_confirmation_is_preserved() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let id = adb_server_command_create(server.lease_id.clone(), fixture.command("echo", true))
        .await
        .unwrap();
    adb_server_command_run(id.clone()).await.unwrap();
    adb_server_command_confirm(id.clone()).await.unwrap();
    adb_server_command_close(id).await.unwrap();
    let claimed = adb_server_claim(server.lease_id).await.unwrap();
    assert!(!claimed.transport_state_unknown);
    let id = adb_server_command_create(claimed.lease_id.clone(), fixture.command("echo", true))
        .await
        .unwrap();
    adb_server_command_run(id.clone()).await.unwrap();
    adb_server_command_close(id).await.unwrap();
    let claimed = adb_server_claim(claimed.lease_id).await.unwrap();
    assert!(claimed.transport_state_unknown);
    adb_server_close(claimed.lease_id).await.unwrap();
}

#[tokio::test]
async fn cleanup_timeout_keeps_server_and_handshake_for_exact_retry() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let id = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let release = CancellationToken::new();
    let held = release.clone();
    let (ready, started) = tokio::sync::oneshot::channel();
    let worker = tokio::spawn(handshake::run_server(
        Some(id.clone()),
        fixture.launch.endpoint.parse().unwrap(),
        move |_, _| async move {
            ready.send(()).unwrap();
            held.cancelled().await;
            Ok(())
        },
    ));
    started.await.unwrap();
    assert_eq!(
        server_owner::close(&server.lease_id, Duration::from_millis(20))
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::CleanupUnconfirmed
    );
    assert!(
        adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id)
    );
    assert!(registry().lock().unwrap().handshakes.contains_key(&id));
    let version = interop_adb::server::query(
        fixture.launch.endpoint.parse().unwrap(),
        "host:version",
        &options(2000, CancellationToken::new()).unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(
        version, b"0029",
        "清理首败必须保留原 Child 供真实流重试收尾"
    );
    release.cancel();
    worker.await.unwrap().unwrap();
    adb_server_close(server.lease_id).await.unwrap();
    assert!(!registry().lock().unwrap().handshakes.contains_key(&id));
}

#[tokio::test]
async fn invalid_ack_and_occupied_endpoint_never_adopt_an_unrelated_listener() {
    let mut fixture = Fixture::new();
    fixture
        .launch
        .environment
        .insert("FIXTURE_BAD_ACK".into(), "1".into());
    let server = adb_server_create(fixture.launch.clone()).await.unwrap();
    assert!(
        adb_server_start(server.lease_id.clone(), 5000)
            .await
            .is_err()
    );
    assert_eq!(
        adb_server_list()
            .await
            .unwrap()
            .into_iter()
            .find(|entry| entry.server_id == server.server_id)
            .unwrap()
            .phase,
        AdbServerPhase::Exited
    );
    adb_server_close(server.lease_id).await.unwrap();
    fixture.launch.environment.remove("FIXTURE_BAD_ACK");
    let listener = tokio::net::TcpListener::bind(&fixture.launch.endpoint)
        .await
        .unwrap();
    let server = adb_server_create(fixture.launch.clone()).await.unwrap();
    assert!(
        adb_server_start(server.lease_id.clone(), 5000)
            .await
            .is_err()
    );
    adb_server_close(server.lease_id).await.unwrap();
    let peer = tokio::net::TcpStream::connect(&fixture.launch.endpoint)
        .await
        .unwrap();
    let (_accepted, _) = listener.accept().await.unwrap();
    drop(peer);
}

#[tokio::test]
async fn claim_cancels_real_smart_socket_and_competing_old_claims_cannot_publish() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let id = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let connecting = tokio::spawn(adb_connect_server(
        fixture.launch.endpoint.clone(),
        "blocked".into(),
        60_000,
        Some(id.clone()),
    ));
    issued(&fixture.marker).await;
    let (first, second) = tokio::join!(
        adb_server_claim(server.lease_id.clone()),
        adb_server_claim(server.lease_id)
    );
    let claimed = match (first, second) {
        (Ok(info), Err(error)) | (Err(error), Ok(info)) => {
            assert_eq!(error.code, AdbServerErrorCode::StaleLease);
            info
        }
        result => panic!("同一旧租约最多一次交接: {result:?}"),
    };
    assert!(connecting.await.unwrap().is_err());
    issued(&fixture.marker.with_extension("closed")).await;
    assert!(adb_handshake_close(id).await.is_ok());
    adb_server_close(claimed.lease_id).await.unwrap();
}

#[tokio::test]
async fn bundled_adb_uses_a_dedicated_ack_and_exact_child_close() {
    let executable =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../.dart_tool/adb/linux/adb");
    if !cfg!(target_os = "linux") || !executable.is_file() {
        return;
    }
    let directory = tempfile::tempdir().unwrap();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = listener.local_addr().unwrap().to_string();
    drop(listener);
    let launch = AdbServerLaunchSpec {
        executable: executable
            .canonicalize()
            .unwrap()
            .to_string_lossy()
            .into_owned(),
        arguments: vec![
            "-L".into(),
            format!(
                "tcp:{}",
                endpoint.parse::<std::net::SocketAddr>().unwrap().port()
            ),
            "--one-device".into(),
            "interop-test-no-usb-device".into(),
            "server".into(),
            "nodaemon".into(),
        ],
        environment: HashMap::from([
            (
                "HOME".into(),
                directory.path().to_string_lossy().into_owned(),
            ),
            (
                "ADB_VENDOR_KEYS".into(),
                directory.path().to_string_lossy().into_owned(),
            ),
            ("ADB_MDNS_AUTO_CONNECT".into(), "0".into()),
            ("ADB_LOCAL_TRANSPORT_MAX_PORT".into(), "0".into()),
        ]),
        endpoint: endpoint.clone(),
    };
    let server = adb_server_create(launch).await.unwrap();
    let ready = adb_server_start(server.lease_id.clone(), 10_000)
        .await
        .unwrap();
    assert!(ready.pid.is_some());
    assert_eq!(ready.phase, AdbServerPhase::Ready);
    let response = interop_adb::server::query(
        endpoint.parse().unwrap(),
        "host:version",
        &options(5000, CancellationToken::new()).unwrap(),
    )
    .await
    .unwrap();
    assert!(!response.is_empty());
    let owner = registry()
        .lock()
        .unwrap()
        .servers
        .get(&server.server_id)
        .unwrap()
        .owner
        .clone();
    adb_server_close(server.lease_id).await.unwrap();
    assert!(
        server_owner::is_finished_for_test(&owner),
        "只在原 Child 实际 wait 完成后确认关闭"
    );
}

#[test]
fn host_close_revokes_servers_before_draining_and_prevents_late_start() {
    const CHILD: &str = "INTEROP_ADB_SERVER_CLOSE_CHILD";
    if std::env::var_os(CHILD).is_none() {
        let status = std::process::Command::new(std::env::current_exe().unwrap()).args(["--exact", "api::server_owner_tests::host_close_revokes_servers_before_draining_and_prevents_late_start", "--nocapture"]).env(CHILD,"1").status().unwrap();
        assert!(status.success());
        return;
    }
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let fixture = Fixture::new();
        let server = fixture.ready().await;
        let id = adb_server_command_create(server.lease_id.clone(), fixture.command("stall", true))
            .await
            .unwrap();
        let command = tokio::spawn(adb_server_command_run(id.clone()));
        issued(&fixture.marker).await;
        let pending = adb_server_handshake_create(server.lease_id.clone())
            .await
            .unwrap();
        adb_close_all().await.unwrap();
        assert_eq!(
            command.await.unwrap().unwrap().status,
            AdbServerCommandStatus::Cancelled
        );
        assert!(adb_server_list().await.unwrap().is_empty());
        assert!(adb_server_start(server.lease_id, 5000).await.is_err());
        assert!(
            handshake::run_server(
                Some(pending),
                fixture.launch.endpoint.parse().unwrap(),
                |_, _| async { Ok(()) }
            )
            .await
            .is_err()
        );
        assert!(!registry().lock().unwrap().closing);
    });
}

#[tokio::test]
async fn command_failed_cleanup_keeps_the_same_id_and_retries_the_same_child() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let id = adb_server_command_create(server.lease_id.clone(), fixture.command("stall", false))
        .await
        .unwrap();
    server_owner::command::fail_terminations_for_test(&id, 2);
    let waiting = tokio::spawn(adb_server_command_run(id.clone()));
    issued(&fixture.marker).await;
    assert_eq!(
        server_owner::command::close(&id, Duration::from_millis(20))
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::CleanupUnconfirmed
    );
    assert!(registry().lock().unwrap().server_commands.contains_key(&id));
    adb_server_command_close(id.clone()).await.unwrap();
    assert_eq!(
        waiting.await.unwrap().unwrap().status,
        AdbServerCommandStatus::Cancelled
    );
    assert!(!registry().lock().unwrap().server_commands.contains_key(&id));
    adb_server_close(server.lease_id).await.unwrap();
}

#[tokio::test]
async fn close_during_startup_prevents_late_ack_from_reopening_admission() {
    let mut fixture = Fixture::new();
    fixture
        .launch
        .environment
        .insert("FIXTURE_DELAY_ACK".into(), "1".into());
    let server = adb_server_create(fixture.launch.clone()).await.unwrap();
    let starting = tokio::spawn(adb_server_start(server.lease_id.clone(), 60_000));
    tokio::time::timeout(Duration::from_secs(5), async {
        while !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id && entry.pid.is_some())
        {
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
    adb_server_close(server.lease_id.clone()).await.unwrap();
    assert!(starting.await.unwrap().is_err());
    assert!(adb_server_handshake_create(server.lease_id).await.is_err());
}

#[tokio::test]
async fn actual_server_exit_revokes_its_clients_and_preserves_a_different_server() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let other_fixture = Fixture::new();
    let other = other_fixture.ready().await;
    let handshake = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let connected = adb_connect_server(
        fixture.launch.endpoint.clone(),
        "device".into(),
        5000,
        Some(handshake.clone()),
    )
    .await
    .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    let client = device(&connected.id).unwrap();
    let borrowed = insert_connection(client.clone(), "borrowed".into(), false).unwrap();
    assert_eq!(
        adb_connection_facts(borrowed.id.clone())
            .unwrap()
            .server_id
            .as_deref(),
        Some(server.server_id.as_str())
    );
    let lifetime = admit_capture(&connected.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    let borrowed_lifetime = admit_capture(&borrowed.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    let mut peer = tokio::net::TcpStream::connect(&fixture.launch.endpoint)
        .await
        .unwrap();
    peer.write_all(b"0008host:die").await.unwrap();
    let mut byte = [0];
    assert_eq!(peer.read(&mut byte).await.unwrap(), 0);
    tokio::time::timeout(Duration::from_secs(2), async {
        lifetime.cancelled().await;
        borrowed_lifetime.cancelled().await;
    })
    .await
    .unwrap();
    assert!(client.is_closed());
    let other_command =
        adb_server_command_create(other.lease_id.clone(), other_fixture.command("echo", false))
            .await
            .unwrap();
    assert_eq!(
        adb_server_command_run(other_command.clone())
            .await
            .unwrap()
            .status,
        AdbServerCommandStatus::Exited
    );
    adb_server_command_close(other_command).await.unwrap();
    adb_server_close(server.lease_id).await.unwrap();
    adb_server_close(other.lease_id).await.unwrap();
}

async fn server_scope() -> AdbAdmissionScopeInfo {
    adb_admission_scope_attach(format!("server-scope-{}", uuid::Uuid::new_v4()), None, 5000)
        .await
        .unwrap()
}

#[tokio::test]
async fn scoped_reservation_rejects_late_create_and_drains_accepted_preparation() {
    let fixture = Fixture::new();
    let first = server_scope().await;
    let server = adb_server_create_scoped(fixture.launch.clone(), first.scope_id.clone())
        .await
        .unwrap();
    let mut spec = fixture.command("stall", false);
    spec.preparation = true;
    let command = adb_server_command_create(server.lease_id.clone(), spec)
        .await
        .unwrap();
    let worker = tokio::spawn(adb_server_command_run(command.clone()));
    issued(&fixture.marker).await;
    let next =
        adb_admission_scope_attach(first.scope_key.clone(), Some(first.scope_id.clone()), 5000)
            .await
            .unwrap();
    assert_eq!(
        worker.await.unwrap().unwrap().status,
        AdbServerCommandStatus::Cancelled
    );
    assert!(
        !registry()
            .lock()
            .unwrap()
            .server_commands
            .contains_key(&command)
    );
    assert!(
        !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id)
    );
    assert!(adb_server_start(server.lease_id, 5000).await.is_err());
    assert_eq!(
        adb_server_create_scoped(fixture.launch.clone(), first.scope_id)
            .await
            .unwrap_err()
            .code,
        AdbServerErrorCode::StaleLease
    );
    assert!(
        !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.launch.endpoint == fixture.launch.endpoint)
    );
    adb_admission_scope_close(next.scope_id, 5000)
        .await
        .unwrap();
}

#[tokio::test]
async fn scoped_takeover_stops_blocked_startup_before_handing_out_successor() {
    let mut fixture = Fixture::new();
    fixture
        .launch
        .environment
        .insert("FIXTURE_DELAY_ACK".into(), "1".into());
    let first = server_scope().await;
    let server = adb_server_create_scoped(fixture.launch.clone(), first.scope_id.clone())
        .await
        .unwrap();
    let starting = tokio::spawn(adb_server_start(server.lease_id.clone(), 60_000));
    tokio::time::timeout(Duration::from_secs(5), async {
        while !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id && entry.pid.is_some())
        {
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
    let next = adb_admission_scope_attach(first.scope_key, Some(first.scope_id), 5000)
        .await
        .unwrap();
    assert!(starting.await.unwrap().is_err());
    assert!(
        !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id)
    );
    assert!(
        tokio::net::TcpStream::connect(&fixture.launch.endpoint)
            .await
            .is_err()
    );
    assert!(adb_server_handshake_create(server.lease_id).await.is_err());
    adb_admission_scope_close(next.scope_id, 5000)
        .await
        .unwrap();
}

#[tokio::test]
async fn scoped_confirmed_server_preserves_connection_and_requires_current_scope_claim() {
    let fixture = Fixture::new();
    let first = server_scope().await;
    let server = adb_server_create_scoped(fixture.launch.clone(), first.scope_id.clone())
        .await
        .unwrap();
    let ready = adb_server_start(server.lease_id.clone(), 5000)
        .await
        .unwrap();
    adb_server_confirm_scoped(server.lease_id.clone(), first.scope_id.clone())
        .await
        .unwrap();
    let handshake = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let connection = adb_connect_server(
        fixture.launch.endpoint.clone(),
        "device".into(),
        5000,
        Some(handshake.clone()),
    )
    .await
    .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    let client = device(&connection.id).unwrap();
    let lifetime = admit_capture(&connection.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    let next =
        adb_admission_scope_attach(first.scope_key.clone(), Some(first.scope_id.clone()), 5000)
            .await
            .unwrap();
    assert!(!client.is_closed());
    assert!(!lifetime.is_cancelled());
    assert_eq!(
        adb_server_list()
            .await
            .unwrap()
            .into_iter()
            .find(|entry| entry.server_id == server.server_id)
            .unwrap()
            .pid,
        ready.pid
    );
    assert!(
        adb_server_claim(server.lease_id.clone()).await.is_err(),
        "无 scope 不能认领有 scope 的资源"
    );
    assert!(
        adb_server_claim_scoped(server.lease_id.clone(), first.scope_id.clone())
            .await
            .is_err()
    );
    assert!(
        adb_server_confirm_scoped(server.lease_id.clone(), first.scope_id)
            .await
            .is_err()
    );
    let claimed = adb_server_claim_scoped(server.lease_id.clone(), next.scope_id.clone())
        .await
        .unwrap();
    adb_server_confirm_scoped(claimed.lease_id.clone(), next.scope_id.clone())
        .await
        .unwrap();
    adb_server_close(server.lease_id).await.unwrap();
    assert!(!client.is_closed());
    let last = adb_admission_scope_attach(first.scope_key, Some(next.scope_id), 5000)
        .await
        .unwrap();
    assert!(!lifetime.is_cancelled());
    adb_server_close(claimed.lease_id).await.unwrap();
    assert!(client.is_closed());
    assert!(lifetime.is_cancelled());
    adb_admission_scope_close(last.scope_id, 5000)
        .await
        .unwrap();
}

#[tokio::test]
async fn scoped_unconfirmed_claim_retains_failed_cleanup_for_scope_retry() {
    let fixture = Fixture::new();
    let server = fixture.ready().await;
    let first = server_scope().await;
    let handshake = adb_server_handshake_create(server.lease_id.clone())
        .await
        .unwrap();
    let release = CancellationToken::new();
    let held = release.clone();
    let (entered, started) = tokio::sync::oneshot::channel();
    let (cancelled, revoked) = tokio::sync::oneshot::channel();
    let worker = tokio::spawn(handshake::run_server(
        Some(handshake),
        fixture.launch.endpoint.parse().unwrap(),
        move |stop, _| async move {
            entered.send(()).unwrap();
            stop.cancelled().await;
            cancelled.send(()).unwrap();
            held.cancelled().await;
            Ok(())
        },
    ));
    started.await.unwrap();
    let claiming = tokio::spawn(adb_server_claim_scoped(
        server.lease_id.clone(),
        first.scope_id.clone(),
    ));
    revoked.await.unwrap();
    assert_eq!(
        adb_admission_scope_attach(first.scope_key.clone(), Some(first.scope_id.clone()), 20)
            .await
            .unwrap_err(),
        "adb_admission_scope_cleanup_unconfirmed"
    );
    let retained = adb_admission_scope_inspect(first.scope_key.clone())
        .unwrap()
        .unwrap();
    assert!(!retained.accepting);
    assert_eq!(retained.scope_id, first.scope_id);
    assert!(
        adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id)
    );
    release.cancel();
    worker.await.unwrap().unwrap();
    assert!(claiming.await.unwrap().is_err());
    let next = adb_admission_scope_attach(first.scope_key, Some(first.scope_id), 5000)
        .await
        .unwrap();
    assert!(
        !adb_server_list()
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.server_id == server.server_id)
    );
    adb_admission_scope_close(next.scope_id, 5000)
        .await
        .unwrap();
}
