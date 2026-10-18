use super::*;
use std::collections::BTreeSet;

async fn inspect(client: &Client, command: &str) -> String {
    let result = client
        .shell(
            command,
            65536,
            OperationOptions {
                timeout: Duration::from_secs(3),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert!(result.exit_code.is_none_or(|code| code == 0));
    String::from_utf8(result.stdout).unwrap()
}

async fn jars(client: &Client) -> BTreeSet<String> {
    inspect(
        client,
        "find /data/local/tmp -maxdepth 1 -type f -name 'interop-companion-*.jar' -print",
    )
    .await
    .lines()
    .map(str::to_owned)
    .collect()
}

// app_process keeps its executable name without --nice-name. Never inspect or
// print argv here: it contains the per-process authentication token.
async fn processes(client: &Client) -> BTreeSet<String> {
    inspect(client, "ps -A -o PID,NAME")
        .await
        .lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let pid = parts.next()?;
            let name = parts.next()?;
            if matches!(
                name,
                "app_process" | "app_process32" | "app_process64" | "com.interop.companion.Main"
            ) {
                Some(pid.to_owned())
            } else {
                None
            }
        })
        .collect()
}

#[tokio::test]
#[ignore = "requires an isolated authorized Android; closes only this test's ADB connection"]
async fn real_companion_transport_loss_removes_its_jar_after_process_exit() {
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT").expect("INTEROP_CORE_TEST_ENDPOINT");
    let address: std::net::SocketAddr = endpoint.parse().unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = runtime
        .invoke(
            "devices.add",
            json!({"address":address.ip().to_string(),"port":address.port()}),
        )
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    runtime
        .invoke("observation.stop", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime
        .store
        .write()
        .await
        .devices
        .iter_mut()
        .find(|d| d.id == id)
        .unwrap()
        .auto_reconnect = false;
    let client = runtime.client(&id).await.unwrap();
    let inspection = Client::connect_tcp(
        &endpoint,
        interop_adb::ConnectOptions {
            identity: Some(runtime.identity.clone()),
            tls: Some(
                interop_adb::wireless::TlsConfig::experimental_rustcrypto(&runtime.identity)
                    .unwrap(),
            ),
            operations: OperationOptions {
                timeout: Duration::from_secs(5),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let before_jars = jars(&inspection).await;
    let before_processes = processes(&inspection).await;
    let helper = Companion::start(
        client.clone(),
        id.clone(),
        runtime.events.clone(),
        CancellationToken::new(),
        Arc::downgrade(&runtime),
    )
    .await
    .unwrap();
    let owned_jars: Vec<_> = jars(&inspection)
        .await
        .difference(&before_jars)
        .cloned()
        .collect();
    assert_eq!(
        owned_jars.len(),
        1,
        "one real temporary JAR must have been deployed"
    );
    let owned_processes: Vec<_> = processes(&inspection)
        .await
        .difference(&before_processes)
        .cloned()
        .collect();
    assert_eq!(
        owned_processes.len(),
        1,
        "one actual Java companion must be running before failure"
    );
    eprintln!(
        "test-owned companion: path={} pid={}",
        owned_jars[0], owned_processes[0]
    );
    client.close(); // No media.shutdown, graceful disconnect, or cleanup via this Client.
    let exited = tokio::time::timeout(Duration::from_secs(10), async {
        while processes(&inspection).await.contains(&owned_processes[0]) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .is_ok();
    let removed = tokio::time::timeout(Duration::from_secs(5), async {
        while jars(&inspection).await.contains(&owned_jars[0]) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .is_ok();
    // Preserve a red assertion while still removing only the exact test-owned
    // artifact. This fallback is never counted as remote automatic cleanup.
    if !removed {
        inspect(
            &inspection,
            &format!("rm -f -- {}", quote(&owned_jars[0]).unwrap()),
        )
        .await;
    }
    helper.stop().await;
    runtime.disconnect_device(&id, false).await.unwrap();
    inspection.close();
    eprintln!(
        "process_exited={exited} automatic_jar_cleanup={removed} fallback_cleanup={}",
        !removed
    );
    assert!(
        exited,
        "the exact companion process must exit after its real ADB transport is closed"
    );
    assert!(
        removed,
        "the companion exited but its JAR was left behind after transport loss"
    );
}

// Exercise the generated script in Android's real non-interactive mksh. A host
// shell or a string assertion cannot validate HUP/job/wait semantics.
#[tokio::test]
#[ignore = "requires an isolated authorized Android shell"]
async fn real_managed_launcher_preserves_exit_and_reaps_interrupted_children() {
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT").expect("INTEROP_CORE_TEST_ENDPOINT");
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let options = interop_adb::ConnectOptions {
        identity: Some(runtime.identity.clone()),
        tls: Some(
            interop_adb::wireless::TlsConfig::experimental_rustcrypto(&runtime.identity).unwrap(),
        ),
        operations: OperationOptions {
            timeout: Duration::from_secs(5),
            ..Default::default()
        },
        ..Default::default()
    };
    let inspection = Client::connect_tcp(&endpoint, options.clone())
        .await
        .unwrap();
    for code in [0, 7] {
        let path = format!(
            "/data/local/tmp/interop-launcher-{}.jar",
            uuid::Uuid::new_v4().simple()
        );
        inspect(
            &inspection,
            &format!("printf fixture > {}", quote(&path).unwrap()),
        )
        .await;
        let script = format!("printf fixture-output; exit {code}");
        let command = managed_shell_command(
            &path,
            &format!("exec /system/bin/sh -c {}", quote(&script).unwrap()),
        )
        .unwrap();
        let result = inspection
            .shell(&command, 4096, OperationOptions::default())
            .await
            .unwrap();
        assert_eq!(result.exit_code, Some(code));
        assert_eq!(result.stdout, b"fixture-output");
        assert_eq!(
            inspect(
                &inspection,
                &format!(
                    "if [ -e {} ]; then printf present; fi",
                    quote(&path).unwrap()
                )
            )
            .await,
            ""
        );
        eprintln!("launcher normal exit={code} removed=true");
    }
    for stopped in [false, true] {
        let path = format!(
            "/data/local/tmp/interop-launcher-{}.jar",
            uuid::Uuid::new_v4().simple()
        );
        let marker = format!("{path}.exit");
        let pid_file = format!("{path}.pid");
        inspect(
            &inspection,
            &format!("printf fixture > {}", quote(&path).unwrap()),
        )
        .await;
        // The child verifies the JAR is still present just before it exits.
        // A stopped child also needs CONT after TERM to run its exit trap.
        let on_term = format!(
            "sleep 0.2; if [ -f {} ]; then printf retained; else printf early-delete; fi > {}; exit 0",
            quote(&path).unwrap(),
            quote(&marker).unwrap()
        );
        let script = format!(
            "trap {} TERM; printf '%s ' \"$$\" > {pid}; cut -d ' ' -f 22 /proc/$$/stat >> {pid}; printf 'INTEROP_COMPANION_READY %s\\n' \"$$\"; {stop}; while :; do sleep 0.05; done",
            quote(&on_term).unwrap(),
            pid = quote(&pid_file).unwrap(),
            stop = if stopped { "kill -STOP $$" } else { ":" }
        );
        let command = managed_shell_command(
            &path,
            &format!("exec /system/bin/sh -c {}", quote(&script).unwrap()),
        )
        .unwrap();
        let client = Client::connect_tcp(&endpoint, options.clone())
            .await
            .unwrap();
        let mut shell = client
            .shell_session(&command, ShellMode::Raw, 4096, OperationOptions::default())
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(5), ready(&mut shell))
            .await
            .unwrap()
            .unwrap();
        client.close();
        let removed = tokio::time::timeout(Duration::from_secs(5), async {
            while inspect(
                &inspection,
                &format!(
                    "if [ -e {} ]; then printf present; fi",
                    quote(&path).unwrap()
                ),
            )
            .await
                == "present"
            {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        })
        .await
        .is_ok();
        // A red test must still clean its own stopped fixture. Only signal
        // the PID whose current argv contains this unique fixture path, never
        // an app_process or another test. This is a test-only fallback and is
        // deliberately not counted as automatic launcher cleanup.
        if !removed {
            let fallback = format!(
                r#"IFS=' ' read -r fixture_pid fixture_starttime < {pid_file}
case "$fixture_pid" in ''|*[!0-9]*) exit 1;; esac
case "$fixture_starttime" in ''|*[!0-9]*) exit 1;; esac
owns_fixture() {{
    [ "$(cut -d ' ' -f 22 /proc/"$fixture_pid"/stat 2>/dev/null)" = "$fixture_starttime" ] &&
    grep -Fq -- {path} /proc/"$fixture_pid"/cmdline 2>/dev/null
}}
if owns_fixture; then kill -TERM "$fixture_pid" 2>/dev/null; fi
if owns_fixture; then kill -CONT "$fixture_pid" 2>/dev/null; fi
attempts=0
while owns_fixture && [ "$attempts" -lt 40 ]; do
    sleep 0.05
    attempts=$((attempts + 1))
done
if owns_fixture; then exit 1; fi
rm -f -- {path} {marker} {pid_file}"#,
                path = quote(&path).unwrap(),
                marker = quote(&marker).unwrap(),
                pid_file = quote(&pid_file).unwrap(),
            );
            inspect(&inspection, &fallback).await;
        }
        let ordering = if removed {
            inspect(&inspection, &format!("cat {}", quote(&marker).unwrap())).await
        } else {
            String::new()
        };
        inspect(
            &inspection,
            &format!(
                "rm -f -- {} {}",
                quote(&marker).unwrap(),
                quote(&pid_file).unwrap()
            ),
        )
        .await;
        assert!(
            removed,
            "launcher failed automatic cleanup; stopped={stopped}; exact fixture cleaned by fallback"
        );
        assert_eq!(ordering, "retained", "JAR must outlive its child");
        eprintln!(
            "launcher transport loss stopped={stopped} removed=true child_kept_jar_until_exit=true"
        );
    }
    inspection.close();
}
