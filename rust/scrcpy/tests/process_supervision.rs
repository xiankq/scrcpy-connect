//! 通用进程监督的主机与被控夹具，不启动应用 Runtime。
#![cfg(target_os = "linux")]
use interop_scrcpy::process::managed_launch_command;

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use interop_scrcpy::shell_quote as quote;
    use std::{
        io::{BufRead, BufReader, Write},
        os::unix::process::CommandExt,
        path::PathBuf,
        process::{Child, Command, Stdio},
        sync::mpsc,
        time::{Duration, Instant, SystemTime, UNIX_EPOCH},
    };

    struct Supervisor {
        process: Child,
        lines: mpsc::Receiver<String>,
        root: PathBuf,
        nonce: String,
        completed: bool,
    }
    impl Supervisor {
        fn launch(body: &str) -> Self {
            let mksh = std::env::var_os("INTEROP_TEST_MKSH")
                .map(PathBuf::from)
                .or_else(|| {
                    ["/bin/mksh", "/usr/bin/mksh"]
                        .map(PathBuf::from)
                        .into_iter()
                        .find(|p| p.is_file())
                });
            let mksh = mksh.expect("requires real mksh: set INTEROP_TEST_MKSH");
            let root = std::env::temp_dir().join(format!(
                "remote-process-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            std::fs::create_dir(&root).unwrap();
            let jar = root.join("owned.jar");
            std::fs::write(&jar, b"fixture").unwrap();
            let child = root.join("child.sh");
            let script = format!(
                "IFS= read -r own_stat < /proc/self/stat\nown_pid=${{own_stat%% *}}\nprint -r -- \"child:$own_pid\"\n{body}\n"
            );
            std::fs::write(&child, script).unwrap();
            let owned_command = format!(
                "exec {} {} {}",
                quote(mksh.to_str().unwrap()).unwrap(),
                quote(child.to_str().unwrap()).unwrap(),
                quote(jar.to_str().unwrap()).unwrap()
            );
            let command = managed_launch_command(jar.to_str().unwrap(), &owned_command).unwrap();
            let mut process = Command::new(mksh)
                .args(["-c", &command])
                .process_group(0)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
            let stdout = process.stdout.take().unwrap();
            let (sender, lines) = mpsc::channel();
            std::thread::spawn(move || {
                for line in BufReader::new(stdout).lines() {
                    if sender.send(line.unwrap()).is_err() {
                        break;
                    }
                }
            });
            Self {
                process,
                lines,
                root,
                nonce: uuid::Uuid::new_v4().simple().to_string(),
                completed: false,
            }
        }
        fn line(&self) -> String {
            self.lines
                .recv_timeout(Duration::from_secs(3))
                .expect("bounded supervisor output")
        }
        fn send(&mut self, action: &str) {
            self.process
                .stdin
                .as_mut()
                .unwrap()
                .write_all(action.as_bytes())
                .unwrap();
        }
        fn exited(&mut self) -> i32 {
            let deadline = Instant::now() + Duration::from_secs(4);
            loop {
                if let Some(status) = self.process.try_wait().unwrap() {
                    self.completed = true;
                    return status.code().expect("supervisor must exit normally");
                }
                assert!(
                    Instant::now() < deadline,
                    "supervisor did not reap its child within the bound"
                );
                std::thread::sleep(Duration::from_millis(5));
            }
        }
        fn start_paused(&mut self) -> (u32, u64) {
            self.send(&format!("START:{}\n", self.nonce));
            let line = self.line();
            interop_scrcpy::process_identity::launch_identity(line.as_bytes()).unwrap()
        }
        fn run(&mut self) {
            self.send(&format!("RUN:{}\n", self.nonce));
        }
        fn stop(&mut self) {
            self.send(&format!("STOP:{}\n", self.nonce));
        }
        fn done(&self) {
            assert_eq!(self.line(), "");
            assert_eq!(self.line(), format!("__INTEROP_DONE__{}", self.nonce));
        }
        fn start(&mut self) -> u32 {
            let (pid, started) = self.start_paused();
            self.run();
            let line = self.line();
            let child = line.strip_prefix("child:").unwrap().parse::<u32>().unwrap();
            assert_eq!(pid, child, "exec must retain the gated process PID");
            // 阻塞夹具立即读取；自然退出夹具可能已被监督器回收。
            if let Ok(stat) = std::fs::read_to_string(format!("/proc/{child}/stat")) {
                let fields = stat.rsplit_once(") ").unwrap().1;
                assert_eq!(
                    fields
                        .split_whitespace()
                        .nth(19)
                        .unwrap()
                        .parse::<u64>()
                        .unwrap(),
                    started
                );
            }
            child
        }
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn gated_open_without_start_has_no_remote_side_effects() {
        let mut supervisor = Supervisor::launch("print -r -- unexpected");
        drop(supervisor.process.stdin.take());
        assert_eq!(supervisor.exited(), 40);
        assert!(
            supervisor.root.join("owned.jar").exists(),
            "未授权的脚本不能删除上传文件"
        );
        assert!(supervisor.lines.try_recv().is_err());
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn stop_before_run_reaps_the_paused_child_without_executing_it() {
        let mut supervisor = Supervisor::launch("print -r -- unexpected");
        let (pid, _) = supervisor.start_paused();
        assert!(
            supervisor
                .lines
                .recv_timeout(Duration::from_millis(20))
                .is_err()
        );
        supervisor.stop();
        supervisor.done();
        assert_eq!(supervisor.exited(), 129);
        assert!(!supervisor.root.join("owned.jar").exists());
        assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn done_follows_real_term_wait_and_preserves_the_jar_until_child_exit() {
        let body = r#"trap 'print -r -- TERM; while [ ! -f "$1.release" ]; do sleep 0.02; done; exit 0' TERM
print -r -- READY
while :; do sleep 0.02; done"#;
        let mut supervisor = Supervisor::launch(body);
        supervisor.start_paused();
        assert!(
            supervisor
                .lines
                .recv_timeout(Duration::from_millis(20))
                .is_err()
        );
        supervisor.run();
        assert!(supervisor.line().starts_with("child:"));
        assert_eq!(supervisor.line(), "READY");
        supervisor.stop();
        assert_eq!(supervisor.line(), "TERM");
        assert!(supervisor.root.join("owned.jar").exists());
        assert!(
            supervisor
                .lines
                .recv_timeout(Duration::from_millis(20))
                .is_err(),
            "尚未 wait 结束不能发布 DONE"
        );
        std::fs::write(supervisor.root.join("owned.jar.release"), b"release").unwrap();
        supervisor.done();
        assert_eq!(supervisor.exited(), 129);
        assert!(!supervisor.root.join("owned.jar").exists());
    }
    impl Drop for Supervisor {
        fn drop(&mut self) {
            if !self.completed {
                // 测试专用私有进程组：即使被测实现遗漏子进程清理，也能回收失败夹具。
                let _ = Command::new("kill")
                    .args(["-KILL", "--", &format!("-{}", self.process.id())])
                    .status();
                let _ = self.process.wait();
            }
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn natural_exit_preserves_status_and_removes_only_its_deployment() {
        for code in [0, 7] {
            let mut supervisor = Supervisor::launch(&format!("exit {code}"));
            std::fs::write(supervisor.root.join("unrelated.jar"), b"unrelated").unwrap();
            supervisor.start();
            supervisor.done();
            assert_eq!(supervisor.exited(), code);
            assert!(!supervisor.root.join("owned.jar").exists());
            assert_eq!(
                std::fs::read(supervisor.root.join("unrelated.jar")).unwrap(),
                b"unrelated"
            );
        }
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn raw_stdin_eof_reaps_blocked_and_stopped_initializers_before_unlink() {
        for stopped in [false, true] {
            let body = format!(
                "trap 'if [ -f \"$1\" ]; then print -nr -- retained > \"$1.exit\"; else print -nr -- early-delete > \"$1.exit\"; fi; exit 0' TERM\nprint -r -- READY\n{}\nwhile :; do sleep 0.02; done",
                if stopped {
                    "kill -STOP \"$own_pid\""
                } else {
                    ":"
                }
            );
            let mut supervisor = Supervisor::launch(&body);
            let child = supervisor.start();
            assert_eq!(supervisor.line(), "READY");
            drop(supervisor.process.stdin.take());
            supervisor.done();
            assert_eq!(supervisor.exited(), 129);
            assert_eq!(
                std::fs::read_to_string(supervisor.root.join("owned.jar.exit")).unwrap(),
                "retained"
            );
            assert!(!supervisor.root.join("owned.jar").exists());
            assert!(
                !std::path::Path::new(&format!("/proc/{child}")).exists(),
                "must reap the exact child"
            );
        }
    }

    #[test]
    #[ignore = "requires real mksh; set INTEROP_TEST_MKSH"]
    fn private_host_stdin_is_not_inherited_and_term_keeps_the_exit_contract() {
        let body = r#"if IFS= read -r leaked; then exit 61; fi
if [ -e /proc/self/fd/3 ]; then exit 62; fi
trap 'if [ -f "$1" ]; then print -nr -- retained > "$1.exit"; fi; exit 0' TERM
print -r -- ISOLATED
while :; do sleep 0.02; done"#;
        let mut supervisor = Supervisor::launch(body);
        let child = supervisor.start();
        assert_eq!(supervisor.line(), "ISOLATED");
        supervisor.send("private-host-keepalive\n");
        std::thread::sleep(Duration::from_millis(20));
        assert!(supervisor.process.try_wait().unwrap().is_none());
        assert!(
            Command::new("kill")
                .args(["-TERM", &supervisor.process.id().to_string()])
                .status()
                .unwrap()
                .success()
        );
        supervisor.done();
        assert_eq!(supervisor.exited(), 143);
        assert_eq!(
            std::fs::read_to_string(supervisor.root.join("owned.jar.exit")).unwrap(),
            "retained"
        );
        assert!(!supervisor.root.join("owned.jar").exists());
        assert!(!std::path::Path::new(&format!("/proc/{child}")).exists());
    }

    #[tokio::test]
    #[ignore = "requires isolated Android raw adbd; deploys only UUID-scoped scrcpy fixtures"]
    async fn actual_scrcpy_accept_stop_and_eof_reap_java_cleanup_and_owned_jar() {
        use interop_adb::{Client, ConnectOptions, OperationOptions, sync::RemotePath};

        async fn inspect(client: &Client, command: &str) -> interop_scrcpy::Result<String> {
            let output = client
                .shell(
                    command,
                    64 * 1024,
                    OperationOptions {
                        timeout: Duration::from_secs(3),
                        ..Default::default()
                    },
                )
                .await?;
            if output.exit_code.is_some_and(|code| code != 0) {
                return Err(interop_scrcpy::Error::new(
                    "fixture_inspection",
                    "Device inspection failed",
                ));
            }
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        }

        async fn upload(client: &Client, path: &str) -> interop_scrcpy::Result<()> {
            let bytes: &[u8] = include_bytes!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../servers/vendor/scrcpy-server-v5.0.1"
            ));
            let count = client
                .sync(OperationOptions {
                    timeout: Duration::from_secs(10),
                    ..Default::default()
                })
                .await?
                .push(
                    &RemotePath::new(path)?,
                    &mut &bytes[..],
                    0o644,
                    0,
                    bytes.len() as u64,
                )
                .await?;
            if count != bytes.len() as u64 {
                return Err(interop_scrcpy::Error::new(
                    "fixture_upload",
                    "Incomplete fixture upload",
                ));
            }
            Ok(())
        }

        async fn starttime(client: &Client, pid: u32) -> interop_scrcpy::Result<u64> {
            let stat = inspect(client, &format!("cat /proc/{pid}/stat")).await?;
            stat.rsplit_once(") ")
                .and_then(|(_, fields)| fields.split_whitespace().nth(19))
                .and_then(|field| field.parse().ok())
                .ok_or_else(|| {
                    interop_scrcpy::Error::new("fixture_identity", "Missing process start time")
                })
        }

        async fn line(stream: &mut interop_adb::AdbStream) -> interop_scrcpy::Result<Vec<u8>> {
            let mut line = Vec::new();
            loop {
                let mut byte = [0];
                stream.read_exact(&mut byte).await?;
                if byte[0] == b'\n' {
                    if line.last() == Some(&b'\r') {
                        line.pop();
                    }
                    return Ok(line);
                }
                line.push(byte[0]);
                if line.len() > 4096 {
                    return Err(interop_scrcpy::Error::new(
                        "fixture_protocol",
                        "监督输出行超过夹具界限。",
                    ));
                }
            }
        }

        let endpoint =
            std::env::var("INTEROP_SCRCPY_TEST_ENDPOINT").expect("INTEROP_SCRCPY_TEST_ENDPOINT");
        let inspection = Client::connect_tcp(&endpoint, ConnectOptions::default())
            .await
            .unwrap();
        // 视频与原始音频均使用唯一生产协议；分别验证主动 STOP 回执和原始 EOF 回收。
        for (video, stop) in [(true, true), (false, false)] {
            let client = Client::connect_tcp(&endpoint, ConnectOptions::default())
                .await
                .unwrap();
            let jar = format!(
                "/data/local/tmp/interop-accept-{}.jar",
                uuid::Uuid::new_v4().simple()
            );
            let nice = format!("interop.accept:{jar}");
            let scid = u32::from_be_bytes(uuid::Uuid::new_v4().as_bytes()[..4].try_into().unwrap())
                & 0x7fff_ffff;
            let socket = format!("@scrcpy_{scid:08x}");
            let mut owned = Vec::<(u32, u64)>::new();
            let mut process = None;
            let nonce = uuid::Uuid::new_v4().simple().to_string();
            let result: interop_scrcpy::Result<()> = async {
                upload(&client, &jar).await?;
                let media = if video { "video=true audio=false control=true" } else { "video=false audio=true control=false audio_codec=raw audio_source=output" };
                let command = format!("CLASSPATH={} exec app_process / --nice-name={} com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn {media} tunnel_forward=true cleanup=true power_on=false", quote(&jar)?, quote(&nice)?);
                process = Some(client.exec(&managed_launch_command(&jar, &command)?, OperationOptions { timeout: Duration::from_secs(20), ..Default::default() }).await?);
                let identity = {
                    let stream = process.as_mut().unwrap();
                    stream.write_all(format!("START:{nonce}\n").as_bytes()).await?;
                    let fields = interop_scrcpy::process_identity::launch_identity(&line(stream).await?)?;
                    owned.push(fields);
                    stream.write_all(format!("RUN:{nonce}\n").as_bytes()).await?;
                    fields
                };
                let deadline = Instant::now() + Duration::from_secs(15);
                let java_pid = loop {
                    let unix = inspect(&inspection, "cat /proc/net/unix").await?;
                    // 检查命令刻意不含夹具名称；仅在宿主内存匹配唯一名称。
                    let ps = inspect(&inspection, "ps -A -o PID,PPID,NAME,ARGS").await?;
                    // Android toybox ps 显示 basename(argv[0])，含路径的 nice-name 在此丢失前缀。
                    let java = ps.lines().find(|line| line.split_whitespace().nth(3) == jar.rsplit('/').next()).and_then(|line| line.split_whitespace().next()).and_then(|field| field.parse::<u32>().ok());
                    let cleanup = java.and_then(|parent| ps.lines().find_map(|line| {
                        let mut fields = line.split_whitespace();
                        let pid = fields.next()?.parse::<u32>().ok()?;
                        let ppid = fields.next()?.parse::<u32>().ok()?;
                        (ppid == parent && line.contains("com.genymobile.scrcpy.CleanUp")).then_some(pid)
                    }));
                    let unlinked = inspect(&inspection, &format!("if [ -e {} ]; then print -nr -- present; fi", quote(&jar)?)).await?.is_empty();
                    if let (Some(java), Some(cleanup)) = (java, cleanup)
                        && unix.lines().any(|line| line.split_whitespace().last() == Some(socket.as_str()))
                        && unlinked
                    {
                        let argv0 = inspect(&inspection, &format!("IFS= read -r -d '' cmd < /proc/{java}/cmdline && print -r -- \"$cmd\"")).await?;
                        if argv0.trim_end() != nice { return Err(interop_scrcpy::Error::new("fixture_identity", "Java argv identity did not match this deployment")); }
                        let java_start = starttime(&inspection, java).await?;
                        if identity != (java, java_start)
                        { return Err(interop_scrcpy::Error::new("fixture_identity", "Exec identity did not match Java")); }
                        owned.push((cleanup, starttime(&inspection, cleanup).await?));
                        eprintln!("scrcpy accept blocked: video={video} stop={stop} socket={socket} java={java} cleanup={cleanup}");
                        break java;
                    }
                    if Instant::now() >= deadline {
                        eprintln!("fixture readiness: unique_socket={} java={java:?} cleanup={cleanup:?} upstream_unlinked={unlinked}", unix.lines().any(|line| line.split_whitespace().last() == Some(socket.as_str())));
                        for line in ps.lines().filter(|line| line.split_whitespace().next() == Some(identity.0.to_string().as_str())) { eprintln!("fixture Java ps: {line}"); }
                        return Err(interop_scrcpy::Error::new("fixture_ready", "Unique listening socket, Java and cleanup child did not become ready"));
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                };
                // CleanUp.main 等待前先自行 unlink；精确重建自有路径，确保停止后的删除确实由本次监督器执行。
                upload(&inspection, &jar).await?;
                if inspect(&inspection, &format!("if [ -f {} ]; then print -nr -- present; fi", quote(&jar)?)).await? != "present" {
                    return Err(interop_scrcpy::Error::new("fixture_witness", "Cleanup witness was not present before EOF"));
                }
                if stop {
                    let stream = process.as_mut().unwrap();
                    stream.write_all(format!("STOP:{nonce}\n").as_bytes()).await?;
                    let done = format!("__INTEROP_DONE__{nonce}");
                    tokio::time::timeout(Duration::from_secs(15), async {
                        loop {
                            if line(stream).await? == done.as_bytes() {
                                return Ok::<_, interop_scrcpy::Error>(());
                            }
                        }
                    }).await.map_err(|_| interop_scrcpy::Error::new(
                        "fixture_cleanup", "未在期限内取得本次监督器的精确 DONE。"
                    ))??;
                }
                process.take().unwrap().close().await?;
                let deadline = Instant::now() + Duration::from_secs(15);
                loop {
                    let ps = inspect(&inspection, "ps -A -o PID,NAME,ARGS").await?;
                    let unix = inspect(&inspection, "cat /proc/net/unix").await?;
                    let mut alive = false;
                    for &(pid, _) in &owned {
                        alive |= !inspect(&inspection, &format!("if [ -e /proc/{pid}/stat ]; then print -nr -- alive; fi")).await?.is_empty();
                    }
                    let present = !inspect(&inspection, &format!("if [ -e {} ]; then print -nr -- present; fi", quote(&jar)?)).await?.is_empty();
                    if !alive && !present && !ps.contains(jar.rsplit('/').next().unwrap()) && !unix.contains(&socket) {
                        eprintln!("scrcpy stopped: video={video} stop={stop} java={java_pid} exact_java_and_cleanup_exited=true jar_removed=true socket_removed=true ps_contains_owned_jar=false");
                        break;
                    }
                    if Instant::now() >= deadline { return Err(interop_scrcpy::Error::new("fixture_cleanup", "Owned Java, cleanup child, socket or JAR remained after raw EOF")); }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
                Ok(())
            }.await;
            drop(process.take());
            client.close();
            if result.is_err() {
                // 失败清理仅操作在父进程及 CleanUp 均被证明属于本夹具时记录的身份。
                for &(pid, started) in &owned {
                    let command = format!(
                        "if IFS= read -r stat < /proc/{pid}/stat; then rest=${{stat##*) }}; set -- $rest; shift 19; if [ \"$1\" = {started} ]; then kill -KILL {pid}; fi; fi"
                    );
                    let _ = inspect(&inspection, &command).await;
                }
                let _ = inspect(&inspection, &format!("rm -f -- {}", quote(&jar).unwrap())).await;
            }
            assert!(result.is_ok(), "video={video} stop={stop}: {result:?}");
        }
        inspection.close();
    }
}
