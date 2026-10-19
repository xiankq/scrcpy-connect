//! One owner for temporary app_process deployments, including legacy raw exec.
use crate::{CoreResult, model::quote};

/// `command` is trusted shell source and must end by exec'ing the owned process
/// (for example `CLASSPATH=... exec app_process ...`). Its stdin is /dev/null;
/// only the supervisor's watcher consumes the host's raw ADB stdin.
///
/// Identity mode gates the child before exec so no child output can precede
/// `__INTEROP_PID__pid:starttime`. Exec preserves both kernel identity fields.
pub(crate) fn managed_shell_command(
    remote_jar: &str,
    command: &str,
    report_identity: bool,
) -> CoreResult<String> {
    let identity_gate = if report_identity {
        r#"IFS= read -r own_stat < /proc/self/stat || exit 40
own_pid=${own_stat%% *}
case "$own_pid" in ''|*[!0-9]*) exit 40 ;; esac
kill -STOP "$own_pid" || exit 40"#
    } else {
        ""
    };
    let identity_report = if report_identity {
        r#"# The child stops itself before exec; wait until that stop is visible.
# No external sleep/toolbox utility is needed on API21. EOF/signal traps remain
# active while waiting, and cleanup also CONTs stopped jobs after TERM.
while :; do
    IFS= read -r stat < /proc/$child/stat || exit 40
    rest=${stat##*) }
    set -- $rest
    state=$1
    shift 19 || exit 40
    started=$1
    case "$started" in ''|*[!0-9]*) exit 40 ;; esac
    case "$state" in T) break ;; Z|X|x) exit 40 ;; esac
done
print -r -- "__INTEROP_PID__$child:$started"
jobs %2 >/dev/null 2>&1
kill -CONT %2 2>/dev/null || exit 40"#
    } else {
        ""
    };
    Ok(format!(
        r#"run_owned() {{
{identity_gate}
{command};
}}
cleanup() {{
    result=$1
    trap - EXIT
    trap '' HUP INT TERM USR1
    # Refresh the supervisor's own job table. Job identities cannot target an
    # unrelated process after a retained numeric PID has been reused.
    for job in %1 %2; do
        jobs "$job" >/dev/null 2>&1
        kill -TERM "$job" 2>/dev/null
        kill -CONT "$job" 2>/dev/null
    done
    if [ -n "${{child:-}}" ]; then wait "$child" 2>/dev/null; fi
    if [ -n "${{watcher:-}}" ]; then wait "$watcher" 2>/dev/null; fi
    rm -f -- {path}
    exit "$result"
}}
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP USR1
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
watch_input() {{ while IFS= read -r keepalive; do :; done; kill -USR1 $$; }}
exec 3<&0
watch_input <&3 &
watcher=$!
exec 3<&-
run_owned </dev/null &
child=$!
{identity_report}
wait "$child"
exit "$?""#,
        path = quote(remote_jar)?
    ))
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
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
        completed: bool,
    }
    impl Supervisor {
        fn launch(identity: bool, body: &str) -> Option<Self> {
            let mksh = std::env::var_os("INTEROP_TEST_MKSH")
                .map(PathBuf::from)
                .or_else(|| {
                    ["/bin/mksh", "/usr/bin/mksh"]
                        .map(PathBuf::from)
                        .into_iter()
                        .find(|p| p.is_file())
                });
            let Some(mksh) = mksh else {
                eprintln!("requires real mksh: set INTEROP_TEST_MKSH");
                return None;
            };
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
            let command = managed_shell_command(
                jar.to_str().unwrap(),
                &format!(
                    "exec {} {} {}",
                    quote(mksh.to_str().unwrap()).unwrap(),
                    quote(child.to_str().unwrap()).unwrap(),
                    quote(jar.to_str().unwrap()).unwrap()
                ),
                identity,
            )
            .unwrap();
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
            Some(Self {
                process,
                lines,
                root,
                completed: false,
            })
        }
        fn line(&self) -> String {
            self.lines
                .recv_timeout(Duration::from_secs(3))
                .expect("bounded supervisor output")
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
        fn child(&self, identity: bool) -> u32 {
            let first = self.line();
            let (identity_pid, started) = if identity {
                let fields = first
                    .strip_prefix("__INTEROP_PID__")
                    .expect("identity must precede all child output");
                let (pid, started) = fields.split_once(':').unwrap();
                (
                    Some(pid.parse::<u32>().unwrap()),
                    Some(started.parse::<u64>().unwrap()),
                )
            } else {
                (None, None)
            };
            let line = if identity { self.line() } else { first };
            let child = line.strip_prefix("child:").unwrap().parse::<u32>().unwrap();
            if let Some(pid) = identity_pid {
                assert_eq!(pid, child, "exec must retain the gated process PID");
                // Read immediately for the blocked fixture; the natural-exit
                // fixture may already have been reaped by its supervisor.
                if let Ok(stat) = std::fs::read_to_string(format!("/proc/{child}/stat")) {
                    let fields = stat.rsplit_once(") ").unwrap().1;
                    assert_eq!(
                        fields
                            .split_whitespace()
                            .nth(19)
                            .unwrap()
                            .parse::<u64>()
                            .unwrap(),
                        started.unwrap()
                    );
                }
            }
            child
        }
    }
    impl Drop for Supervisor {
        fn drop(&mut self) {
            if !self.completed {
                // Test-only private process group: reap failed fixtures even
                // when the implementation under test misses its child cleanup.
                let _ = Command::new("kill")
                    .args(["-KILL", "--", &format!("-{}", self.process.id())])
                    .status();
                let _ = self.process.wait();
            }
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn natural_exit_preserves_status_and_removes_only_its_deployment() {
        for identity in [false, true] {
            for code in [0, 7] {
                let Some(mut supervisor) = Supervisor::launch(identity, &format!("exit {code}"))
                else {
                    return;
                };
                std::fs::write(supervisor.root.join("unrelated.jar"), b"unrelated").unwrap();
                supervisor.child(identity);
                assert_eq!(supervisor.exited(), code);
                assert!(!supervisor.root.join("owned.jar").exists());
                assert_eq!(
                    std::fs::read(supervisor.root.join("unrelated.jar")).unwrap(),
                    b"unrelated"
                );
            }
        }
    }

    #[test]
    fn raw_stdin_eof_reaps_blocked_and_stopped_initializers_before_unlink() {
        for identity in [false, true] {
            for stopped in [false, true] {
                let body = format!(
                    "trap 'if [ -f \"$1\" ]; then print -nr -- retained > \"$1.exit\"; else print -nr -- early-delete > \"$1.exit\"; fi; exit 0' TERM\nprint -r -- READY\n{}\nwhile :; do sleep 0.02; done",
                    if stopped {
                        "kill -STOP \"$own_pid\""
                    } else {
                        ":"
                    }
                );
                let Some(mut supervisor) = Supervisor::launch(identity, &body) else {
                    return;
                };
                let child = supervisor.child(identity);
                assert_eq!(supervisor.line(), "READY");
                drop(supervisor.process.stdin.take());
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
    }

    #[test]
    fn private_host_stdin_is_not_inherited_and_term_keeps_the_exit_contract() {
        for identity in [false, true] {
            let body = r#"if IFS= read -r leaked; then exit 61; fi
if [ -e /proc/self/fd/3 ]; then exit 62; fi
trap 'if [ -f "$1" ]; then print -nr -- retained > "$1.exit"; fi; exit 0' TERM
print -r -- ISOLATED
while :; do sleep 0.02; done"#;
            let Some(mut supervisor) = Supervisor::launch(identity, body) else {
                return;
            };
            let child = supervisor.child(identity);
            assert_eq!(supervisor.line(), "ISOLATED");
            supervisor
                .process
                .stdin
                .as_mut()
                .unwrap()
                .write_all(b"private-host-keepalive\n")
                .unwrap();
            std::thread::sleep(Duration::from_millis(20));
            assert!(supervisor.process.try_wait().unwrap().is_none());
            assert!(
                Command::new("kill")
                    .args(["-TERM", &supervisor.process.id().to_string()])
                    .status()
                    .unwrap()
                    .success()
            );
            assert_eq!(supervisor.exited(), 143);
            assert_eq!(
                std::fs::read_to_string(supervisor.root.join("owned.jar.exit")).unwrap(),
                "retained"
            );
            assert!(!supervisor.root.join("owned.jar").exists());
            assert!(!std::path::Path::new(&format!("/proc/{child}")).exists());
        }
    }

    #[tokio::test]
    #[ignore = "requires isolated Android raw adbd; deploys only UUID-scoped scrcpy fixtures"]
    async fn actual_scrcpy_accept_eof_reaps_java_cleanup_and_owned_jar() {
        use interop_adb::{Client, ConnectOptions, OperationOptions, sync::RemotePath};

        async fn inspect(client: &Client, command: &str) -> crate::CoreResult<String> {
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
                return Err(crate::CoreError::new(
                    "fixture_inspection",
                    "Device inspection failed",
                ));
            }
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        }

        async fn upload(client: &Client, path: &str) -> crate::CoreResult<()> {
            let bytes = crate::bundled_servers::get("scrcpy")?;
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
                return Err(crate::CoreError::new(
                    "fixture_upload",
                    "Incomplete fixture upload",
                ));
            }
            Ok(())
        }

        async fn starttime(client: &Client, pid: u32) -> crate::CoreResult<u64> {
            let stat = inspect(client, &format!("cat /proc/{pid}/stat")).await?;
            stat.rsplit_once(") ")
                .and_then(|(_, fields)| fields.split_whitespace().nth(19))
                .and_then(|field| field.parse().ok())
                .ok_or_else(|| {
                    crate::CoreError::new("fixture_identity", "Missing process start time")
                })
        }

        let endpoint =
            std::env::var("INTEROP_CORE_TEST_ENDPOINT").expect("INTEROP_CORE_TEST_ENDPOINT");
        let inspection = Client::connect_tcp(&endpoint, ConnectOptions::default())
            .await
            .unwrap();
        for report_identity in [true, false] {
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
            let result: crate::CoreResult<()> = async {
                upload(&client, &jar).await?;
                let media = if report_identity { "video=true audio=false control=true" } else { "video=false audio=true control=false audio_codec=raw audio_source=output" };
                let command = format!("CLASSPATH={} exec app_process / --nice-name={} com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn {media} tunnel_forward=true cleanup=true power_on=false", quote(&jar)?, quote(&nice)?);
                process = Some(client.exec(&managed_shell_command(&jar, &command, report_identity)?, OperationOptions { timeout: Duration::from_secs(20), ..Default::default() }).await?);
                let identity = if report_identity {
                    let stream = process.as_mut().unwrap();
                    let mut line = Vec::new();
                    loop {
                        let mut byte = [0];
                        stream.read_exact(&mut byte).await?;
                        if byte[0] == b'\n' { break; }
                        line.push(byte[0]);
                        if line.len() > 64 { return Err(crate::CoreError::new("fixture_identity", "Oversized identity line")); }
                    }
                    let text = String::from_utf8_lossy(&line);
                    let (pid, started) = text.strip_prefix("__INTEROP_PID__").and_then(|fields| fields.split_once(':')).ok_or_else(|| crate::CoreError::new("fixture_identity", "Missing identity receipt"))?;
                    let fields = (pid.parse::<u32>().unwrap(), started.parse::<u64>().unwrap());
                    owned.push(fields);
                    Some(fields)
                } else { None };
                let deadline = Instant::now() + Duration::from_secs(15);
                let java_pid = loop {
                    let unix = inspect(&inspection, "cat /proc/net/unix").await?;
                    // The inspection command deliberately contains no fixture
                    // name; match the unique names only in host memory.
                    let ps = inspect(&inspection, "ps -A -o PID,PPID,NAME,ARGS").await?;
                    // Android toybox ps displays basename(argv[0]), so a
                    // nice-name containing our path loses its prefix here.
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
                        if argv0.trim_end() != nice { return Err(crate::CoreError::new("fixture_identity", "Java argv identity did not match this deployment")); }
                        let java_start = starttime(&inspection, java).await?;
                        if let Some(expected) = identity
                            && expected != (java, java_start)
                        { return Err(crate::CoreError::new("fixture_identity", "Exec identity did not match Java")); }
                        if identity.is_none() { owned.push((java, java_start)); }
                        owned.push((cleanup, starttime(&inspection, cleanup).await?));
                        eprintln!("scrcpy accept blocked: identity={report_identity} socket={socket} java={java} cleanup={cleanup}");
                        break java;
                    }
                    if Instant::now() >= deadline {
                        eprintln!("fixture readiness: unique_socket={} java={java:?} cleanup={cleanup:?} upstream_unlinked={unlinked}", unix.lines().any(|line| line.split_whitespace().last() == Some(socket.as_str())));
                        for line in ps.lines().filter(|line| identity.is_some_and(|(pid, _)| line.split_whitespace().next() == Some(pid.to_string().as_str()))) { eprintln!("fixture Java ps: {line}"); }
                        return Err(crate::CoreError::new("fixture_ready", "Unique listening socket, Java and cleanup child did not become ready"));
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                };
                // CleanUp.main self-unlinks before waiting. Recreate exactly
                // our own path after witnessing that unlink, so deletion after
                // EOF proves the supervisor acted rather than a preexisting absence.
                upload(&inspection, &jar).await?;
                if inspect(&inspection, &format!("if [ -f {} ]; then print -nr -- present; fi", quote(&jar)?)).await? != "present" {
                    return Err(crate::CoreError::new("fixture_witness", "Cleanup witness was not present before EOF"));
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
                        eprintln!("scrcpy raw EOF: identity={report_identity} java={java_pid} exact_java_and_cleanup_exited=true jar_removed=true socket_removed=true ps_contains_owned_jar=false");
                        break;
                    }
                    if Instant::now() >= deadline { return Err(crate::CoreError::new("fixture_cleanup", "Owned Java, cleanup child, socket or JAR remained after raw EOF")); }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
                Ok(())
            }.await;
            drop(process.take());
            client.close();
            if result.is_err() {
                // Failure cleanup is scoped to identities recorded while both
                // parent and CleanUp were proven to belong to this fixture.
                for &(pid, started) in &owned {
                    let command = format!(
                        "if IFS= read -r stat < /proc/{pid}/stat; then rest=${{stat##*) }}; set -- $rest; shift 19; if [ \"$1\" = {started} ]; then kill -KILL {pid}; fi; fi"
                    );
                    let _ = inspect(&inspection, &command).await;
                }
                let _ = inspect(&inspection, &format!("rm -f -- {}", quote(&jar).unwrap())).await;
            }
            assert!(result.is_ok(), "identity={report_identity}: {result:?}");
        }
        inspection.close();
    }
}
