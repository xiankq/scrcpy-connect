//! Concrete display execution. Ratio selection belongs to the Dart caller.
use crate::{CoreError, CoreResult, model::quote};
use serde_json::Value;

const LEASE: &str = "/data/local/tmp/interop-display-0";

pub(super) fn dimensions(params: &Value) -> CoreResult<Option<(u16, u16)>> {
    dimensions_with_minimum(params, 320)
}

/// Virtual display pixels are already resolved by the caller's ratio and media
/// policy. Small dimensions do not override the physical Android display.
pub(super) fn virtual_dimensions(params: &Value) -> CoreResult<Option<(u16, u16)>> {
    dimensions_with_minimum(params, 2)
}

fn dimensions_with_minimum(params: &Value, minimum: u64) -> CoreResult<Option<(u16, u16)>> {
    if params.get("displayWidth").is_none() && params.get("displayHeight").is_none() {
        return Ok(None);
    }
    let dimension = |key: &str| {
        params[key]
            .as_u64()
            .filter(|n| (minimum..=4096).contains(n))
            .map(|n| n as u16)
            .ok_or_else(|| {
                CoreError::new(
                    "invalid_argument",
                    format!("显示宽高必须在 {minimum} 到 4096 像素之间。"),
                )
            })
    };
    Ok(Some((
        dimension("displayWidth")?,
        dimension("displayHeight")?,
    )))
}

/// Android's effective physical pixel/density settings, including a user override.
pub(super) async fn physical_metrics(client: &interop_adb::Client) -> CoreResult<(u32, u32, u32)> {
    let receipt = client
        .shell(
            "wm size; wm density",
            8192,
            interop_adb::OperationOptions::default(),
        )
        .await?;
    let text = String::from_utf8_lossy(&receipt.stdout);
    parse_metrics(&text).ok_or_else(|| {
        CoreError::new(
            "display_metrics_unavailable",
            "无法核实手机屏幕尺寸和密度，未更改独立窗口。",
        )
    })
}

fn parse_metrics(text: &str) -> Option<(u32, u32, u32)> {
    let mut size = None;
    let mut density = None;
    for line in text.lines() {
        if let Some(value) = line
            .strip_prefix("Physical size: ")
            .or_else(|| line.strip_prefix("Override size: "))
        {
            let (width, height) = value.trim().split_once('x')?;
            size = Some((width.parse::<u32>().ok()?, height.parse::<u32>().ok()?));
        }
        if let Some(value) = line
            .strip_prefix("Physical density: ")
            .or_else(|| line.strip_prefix("Override density: "))
        {
            density = value.trim().parse::<u32>().ok();
        }
    }
    let (width, height) = size?;
    let dpi = density?;
    (width > 0 && height > 0 && dpi > 0).then_some((width, height, dpi))
}

pub(super) fn scaled_density(metrics: (u32, u32, u32), width: u16, height: u16) -> u32 {
    let (physical_width, physical_height, dpi) = metrics;
    // Preserve the device's logical short side across encoder resolution and
    // orientation. A portrait phone remains a phone at 720p and 1080p alike.
    ((u64::from(dpi) * u64::from(width.min(height))
        + u64::from(physical_width.min(physical_height)) / 2)
        / u64::from(physical_width.min(physical_height)))
    .clamp(72, 65535) as u32
}

pub(super) async fn virtual_ids(client: &interop_adb::Client) -> CoreResult<Vec<u32>> {
    let receipt = client
        .shell(
            "dumpsys display",
            1_048_576,
            interop_adb::OperationOptions::default(),
        )
        .await?;
    let text = String::from_utf8_lossy(&receipt.stdout);
    let mut ids = Vec::new();
    for line in text.lines() {
        if let Some((_, tail)) = line.split_once("DisplayInfo{\"scrcpy\", displayId ")
            && let Some(id) = tail.split(',').next().and_then(|id| id.parse::<u32>().ok())
            && !ids.contains(&id)
        {
            ids.push(id);
        }
    }
    Ok(ids)
}

pub(super) async fn new_virtual_id(
    client: &interop_adb::Client,
    previous: &[u32],
) -> CoreResult<u32> {
    let ids = virtual_ids(client)
        .await?
        .into_iter()
        .filter(|id| !previous.contains(id))
        .collect::<Vec<_>>();
    if ids.len() != 1 {
        return Err(CoreError::new(
            "display_identity_unverified",
            "无法唯一核实新虚拟屏幕；已有应用任务保持不变。",
        ));
    }
    Ok(ids[0])
}

pub(super) async fn task(
    client: &interop_adb::Client,
    package: &str,
    display: u32,
) -> CoreResult<u32> {
    let receipt = client
        .shell(
            "cmd activity stack list",
            262_144,
            interop_adb::OperationOptions::default(),
        )
        .await?;
    let text = String::from_utf8_lossy(&receipt.stdout);
    parse_task(&text, package, display).ok_or_else(|| {
        CoreError::new(
            "task_identity_unverified",
            "无法唯一核实独立窗口的现有应用任务；未重新启动应用。",
        )
    })
}

fn parse_task(text: &str, package: &str, display: u32) -> Option<u32> {
    let mut root = None;
    let mut found = Vec::new();
    let mut children = std::collections::HashMap::<u32, usize>::new();
    for line in text.lines() {
        if let Some(tail) = line.strip_prefix("RootTask id=") {
            let id = tail
                .split_whitespace()
                .next()
                .and_then(|id| id.parse::<u32>().ok());
            let display_id = line
                .split("displayId=")
                .nth(1)
                .and_then(|tail| tail.split_whitespace().next())
                .and_then(|id| id.parse::<u32>().ok());
            root = id.zip(display_id);
        } else if line.trim_start().starts_with("taskId=")
            && let Some((id, target)) = root
        {
            *children.entry(id).or_default() += 1;
            if target == display && line.contains(&format!(": {package}/")) && !found.contains(&id)
            {
                found.push(id);
            }
        }
    }
    // move-stack migrates a root task. Refuse a grouped root containing other
    // tasks rather than implicitly moving unrelated applications with it.
    if found.len() == 1 && children.get(&found[0]) == Some(&1) {
        Some(found[0])
    } else {
        None
    }
}

pub(super) async fn move_task(
    client: &interop_adb::Client,
    task: u32,
    display: u32,
) -> CoreResult<()> {
    let receipt = client
        .shell(
            &format!("cmd activity display move-stack {task} {display}"),
            8192,
            interop_adb::OperationOptions::default(),
        )
        .await?;
    if receipt.exit_code != Some(0) || !receipt.stderr.is_empty() {
        return Err(CoreError::new(
            "task_move_failed",
            "系统未确认原应用任务迁移，窗口可重试。",
        ));
    }
    Ok(())
}

// Android wm's labels are fixed by WindowManagerShellCommand on API21+.
// Ignore the physical size: only the pre-existing override must be restored.
const READ_SIZE: &str = r#"read_override() {
    override=reset
    report=$(wm size) || return 1
    while IFS= read -r line; do
        case "$line" in 'Override size: '*) override=${line#'Override size: '} ;; esac
    done <<INTEROP_SIZE
$report
INTEROP_SIZE
    case "$override" in reset) ;; *[!0-9x]*|'') return 1 ;; esac
}"#;

const READ_ROTATION: &str = r#"read_rotation() {
    rotation=
    report=$(dumpsys input) || return 1
    while IFS= read -r line; do
        case "$line" in
            *'Viewport '*displayId=0,*orientation=*)
                rotation=${line#*orientation=}; rotation=${rotation%%,*}; break ;;
            *'SurfaceOrientation: '*) rotation=${line#*'SurfaceOrientation: '} ;;
        esac
    done <<INTEROP_ROTATION
$report
INTEROP_ROTATION
    case "$rotation" in 0|2) natural_size=$desired_width'x'$desired_height ;;
        1|3) natural_size=$desired_height'x'$desired_width ;; *) return 1 ;; esac
}"#;

// A symlink publishes the complete lock identity atomically without Android's
// SELinux-restricted hard-link operation. A mkdir followed
// by writing a PID leaves an unrecoverable anonymous lock if the shell is killed
// between those operations. PID start time prevents a reused PID retaining it.
const LEASE_LOCK: &str = r#"lease_ours() {
    current_owner=
    IFS= read -r current_owner 2>/dev/null < "$lease/owner" || return 1
    [ "$current_owner" = "$lease_owner" ]
}
process_start() {
    IFS= read -r process_stat 2>/dev/null < "/proc/$1/stat" || return 1
    process_fields=${process_stat##*) }
    set -- $process_fields
    case "$1" in Z|X|'') return 1 ;; esac
    shift 19 || return 1
    process_started=$1
}
process_start "$$" || exit 45
lock_identity="$$:$process_started:$lease_owner"
lock_file="$lease/.lock-$lease_owner-$$-$process_started"
worker_file="$lease/worker-$lease_owner-$$-$process_started"
closing="$lease/closing-$lease_owner"
prepare_lock() {
    lease_ours || return 1
    printf '%s\n' "$lock_identity" > "$lock_file"
}
lock_taken() {
    held_identity=
    IFS= read -r held_identity 2>/dev/null < "$lease/busy" || return 1
    [ "$held_identity" = "$lock_identity" ]
}
release_lock() {
    if lock_taken; then rm -f -- "$lease/busy"; fi
    rm -f -- "$lock_file"
}
try_lock() { [ ! -d "$lease/busy" ] && ln -s "$lock_file" "$lease/busy" 2>/dev/null; }
busy_alive() {
    busy_identity=
    IFS= read -r busy_identity 2>/dev/null < "$lease/busy" || return 2
    IFS=: read -r busy_pid busy_started busy_owner <<INTEROP_BUSY
$busy_identity
INTEROP_BUSY
    case "$busy_pid:$busy_started" in *[!0-9:]*|:*|*:) return 2 ;; esac
    [ "$busy_owner" = "$lease_owner" ] || return 2
    if process_start "$busy_pid" && [ "$process_started" = "$busy_started" ]; then return 0; fi
    # The host-facing shell may be killed while wm is still inside Binder.
    # Its gated worker was published before it could execute any mutation.
    worker_identity=
    IFS= read -r worker_identity 2>/dev/null < "$lease/worker-$busy_owner-$busy_pid-$busy_started" || return 1
    IFS=: read -r worker_pid worker_started worker_lock <<INTEROP_WORKER
$worker_identity
INTEROP_WORKER
    [ "$worker_lock" = "$busy_identity" ] || return 1
    case "$worker_pid:$worker_started" in *[!0-9:]*|:*|*:) return 2 ;; esac
    process_start "$worker_pid" && [ "$process_started" = "$worker_started" ]
}
restore_owned() {
    lease_ours || return 0
    IFS= read -r target < "$lease/target" || return 1
    IFS= read -r original < "$lease/original" || return 1
    pending=
    if [ -f "$lease/pending" ]; then IFS= read -r pending < "$lease/pending"; fi
    read_override || return 1
    if [ "$override" = "$target" ] || [ "$override" = "$pending" ]; then
        wm size "$original" >&2 || return 1
        read_override && [ "$override" = "$original" ] || return 1
    fi
    # An outside edit has a different value and is intentionally preserved.
    lease_ours && lock_taken && rm -rf -- "$lease"
}"#;

// This worker ignores transport signals once admitted. Its real PID/start time
// is published before the parent opens the gate. If the parent dies before that
// handoff it exits without running wm; afterwards the capture supervisor waits
// for this exact process, including a slow Binder call, before restoring pixels.
const WM_WORKER: &str = r#"lease=$1
lease_owner=$2
expected_lock=$3
desired=$4
worker_file=$5
trap '' HUP INT TERM USR1
read_parent() {
    IFS= read -r parent_stat 2>/dev/null < "/proc/$parent_pid/stat" || return 1
    parent_fields=${parent_stat##*) }
    set -- $parent_fields
    case "$1" in Z|X|'') return 1 ;; esac
    shift 19 || return 1
    [ "$1" = "$parent_started" ]
}
IFS=: read -r parent_pid parent_started parent_owner <<INTEROP_PARENT
$expected_lock
INTEROP_PARENT
IFS= read -r own_stat < "/proc/$$/stat" || exit 45
own_fields=${own_stat##*) }
set -- $own_fields
shift 19 || exit 45
worker_identity="$$:$1:$expected_lock"
# The immutable request identity is the capability for this worker's gate.
IFS= read -r held 2>/dev/null < "$lease/busy" || exit 41
[ "$held" = "$expected_lock" ] || exit 41
printf '%s\n' "$worker_identity" > "$worker_file.$$" || exit 41
mv "$worker_file.$$" "$worker_file" || exit 41
while :; do
    [ ! -f "$worker_file.abort" ] || exit 41
    IFS= read -r owner 2>/dev/null < "$lease/owner" || exit 41
    IFS= read -r held 2>/dev/null < "$lease/busy" || exit 41
    [ "$owner" = "$lease_owner" ] && [ "$held" = "$expected_lock" ] || exit 41
    go=
    if [ -f "$worker_file.go" ]; then IFS= read -r go < "$worker_file.go"; fi
    if [ "$go" = "$expected_lock" ]; then break; fi
    read_parent || exit 41
    sleep .01
done
exec wm size "$desired""#;

fn lease_owner(owner: &str) -> CoreResult<String> {
    if owner.is_empty()
        || !owner
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
    {
        return Err(CoreError::new("invalid_argument", "显示尺寸租约标识无效。"));
    }
    quote(owner)
}

/// A device-side lease follows the supervised process, including host EOF.
/// The closing tombstone fences new resizes; a live resize keeps ownership until
/// its trapped cleanup completes. An atomically published dead owner is reaped.
pub(super) fn supervise(command: &str, owner: &str, width: u16, height: u16) -> CoreResult<String> {
    let owner = lease_owner(owner)?;
    let command = quote(command)?;
    Ok(format!(
        r#"{READ_SIZE}
{READ_ROTATION}
desired_width={width}
desired_height={height}
read_rotation || {{ echo 'main display rotation could not be verified' >&2; exit 44; }}
lease={LEASE}
lease_owner={owner}
mkdir "$lease" 2>/dev/null || {{ echo 'display override already owned by another session' >&2; exit 41; }}
echo "$lease_owner" > "$lease/owner"
read_override || {{ rm -rf -- "$lease"; exit 42; }}
original=$override
echo "$original" > "$lease/original"
echo "$natural_size" > "$lease/target"
{LEASE_LOCK}
restore_display() {{
    result=$?
    trap - EXIT
    trap '' HUP INT TERM USR1
    lease_ours || exit "$result"
    # A stale supervisor cannot fence a subsequent capture using the same path.
    : > "$closing"
    prepare_lock || exit "$result"
    while ! try_lock; do
        lease_ours || {{ release_lock; exit "$result"; }}
        busy_alive
        alive=$?
        if [ "$alive" = 1 ]; then
            # Only this capture's supervisor reaps a dead request. New resizes
            # are already fenced, and an alive request always releases itself.
            observed=$busy_identity
            IFS= read -r confirmed 2>/dev/null < "$lease/busy"
            if [ "$observed" = "$confirmed" ]; then rm -f -- "$lease/busy"; fi
        elif [ "$alive" != 0 ]; then
            echo 'display resize lock identity could not be verified' >&2
            release_lock
            exit 43
        else
            sleep .05
        fi
    done
    if ! restore_owned; then
        echo 'display override restoration could not be verified' >&2
        release_lock
        exit 43
    fi
    release_lock
    exit "$result"
}}
trap restore_display EXIT
trap 'exit 129' HUP USR1
trap 'exit 130' INT
trap 'exit 143' TERM
wm size "$natural_size" >&2 || exit 43
read_override && [ "$override" = "$natural_size" ] || exit 43
/system/bin/sh -c {command}
exit "$?""#
    ))
}

pub(super) fn resize(owner: &str, width: u16, height: u16) -> CoreResult<String> {
    let owner = lease_owner(owner)?;
    let worker = quote(WM_WORKER)?;
    Ok(format!(
        r#"{READ_SIZE}
{READ_ROTATION}
desired_width={width}
desired_height={height}
read_rotation || exit 44
lease={LEASE}
lease_owner={owner}
{LEASE_LOCK}
finish_resize() {{
    result=$?
    trap - EXIT
    trap '' HUP INT TERM USR1
    if lock_taken && lease_ours; then
        # Abort an uncommitted gate, but never restore ahead of a wm process
        # that was already admitted. wait retains this shell's exact job owner.
        : > "$worker_file.abort"
        if [ -n "${{wm_pid:-}}" ]; then wait "$wm_pid" 2>/dev/null; fi
        if [ -f "$closing" ]; then
            restore_owned || result=43
        else
            # Signals may arrive after wm applied pixels but before the caller
            # recorded its receipt. Reconcile that owned intent before unlock.
            if [ -f "$lease/pending" ] && read_override && [ "$override" = "$natural_size" ]; then
                echo "$natural_size" > "$lease/target"
                rm -f -- "$lease/pending"
            fi
            rm -f -- "$worker_file" "$worker_file.go" "$worker_file.abort"
        fi
    fi
    release_lock
    exit "$result"
}}
trap finish_resize EXIT
trap 'exit 129' HUP USR1
trap 'exit 130' INT
trap 'exit 143' TERM
lease_ours && [ ! -f "$closing" ] || exit 41
prepare_lock && try_lock || exit 41
lease_ours && [ ! -f "$closing" ] || exit 41
IFS= read -r target < "$lease/target"
read_override && [ "$override" = "$target" ] || exit 42
# Publish intent before the system call: cancellation may lose its reply after
# Android has applied the new size. Closing can restore either confirmed value.
echo "$natural_size" > "$lease/pending"
rm -f -- "$worker_file" "$worker_file.go" "$worker_file.abort"
/system/bin/sh -c {worker} interop-wm "$lease" "$lease_owner" "$lock_identity" "$natural_size" "$worker_file" &
wm_pid=$!
# No physical change is allowed until the exact live worker is observable.
while :; do
    worker_identity=
    if IFS= read -r worker_identity 2>/dev/null < "$worker_file"; then
        case "$worker_identity" in "$wm_pid":*:"$lock_identity") break ;; esac
    fi
    process_start "$wm_pid" || exit 43
    sleep .01
done
echo "$lock_identity" > "$worker_file.go"
wait "$wm_pid" || exit 43
read_override || exit 43
[ "$override" = "$natural_size" ] || exit 43
echo "$natural_size" > "$lease/target"
rm -f -- "$lease/pending"
echo __INTEROP_DISPLAY_READY__"#
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn task_identity_rejects_grouped_or_ambiguous_roots() {
        let single = "RootTask id=77 bounds=[] displayId=3 userId=0\n taskId=77: com.android.settings/.Settings bounds=[]";
        assert_eq!(parse_task(single, "com.android.settings", 3), Some(77));
        assert_eq!(parse_task(single, "com.android.settings", 0), None);
        assert_eq!(
            parse_task(
                &format!("{single}\n taskId=88: com.example.other/.Main bounds=[]"),
                "com.android.settings",
                3
            ),
            None
        );
        assert_eq!(
            parse_task(
                &format!(
                    "{single}\nRootTask id=78 displayId=3 userId=0\n taskId=78: com.android.settings/.Settings"
                ),
                "com.android.settings",
                3
            ),
            None
        );
    }

    #[test]
    fn density_preserves_phone_dp_and_effective_overrides() {
        let metrics = parse_metrics("Physical size: 1080x2400\nPhysical density: 420").unwrap();
        assert_eq!(scaled_density(metrics, 720, 1280), 280);
        assert_eq!(scaled_density(metrics, 1280, 720), 280);
        assert_eq!(scaled_density(metrics, 1080, 1920), 420);
        assert_eq!(
            parse_metrics(
                "Physical size: 1080x2400\nOverride size: 800x1600\nPhysical density: 420\nOverride density: 320"
            ),
            Some((800, 1600, 320))
        );
    }
    #[tokio::test]
    #[ignore = "requires INTEROP_ADBD_PORT and temporarily overrides the real Android display"]
    async fn real_android_supervised_output_and_original_override_are_preserved() {
        let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
        let client = interop_adb::Client::connect_tcp(
            ("127.0.0.1", port),
            interop_adb::ConnectOptions::default(),
        )
        .await
        .unwrap();
        let original = client
            .shell("wm size", 4096, interop_adb::OperationOptions::default())
            .await
            .unwrap()
            .stdout;
        let script = supervise(
            "echo __INTEROP_PROBE_READY__",
            &uuid::Uuid::new_v4().to_string(),
            640,
            960,
        )
        .unwrap();
        let output = client
            .shell(&script, 4096, interop_adb::OperationOptions::default())
            .await
            .unwrap();
        eprintln!(
            "supervisor marker stdout={:?}, stderr={:?}, exit={:?}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
            output.exit_code
        );
        let restored = client
            .shell("wm size", 4096, interop_adb::OperationOptions::default())
            .await
            .unwrap()
            .stdout;
        let probe_path = format!(
            "/data/local/tmp/interop-display-probe-{}.jar",
            uuid::Uuid::new_v4()
        );
        let body = crate::remote_process::managed_shell_command(
            &probe_path,
            "exec /system/bin/sh -c 'echo __INTEROP_NESTED_READY__; sleep 1'",
            true,
        )
        .unwrap();
        let script = supervise(&body, &uuid::Uuid::new_v4().to_string(), 640, 960).unwrap();
        let mut stream = client
            .exec(&script, interop_adb::OperationOptions::default())
            .await
            .unwrap();
        let mut nested = Vec::new();
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            let mut buffer = [0; 4096];
            loop {
                let size = stream.read(&mut buffer).await.unwrap();
                if size == 0 {
                    break;
                }
                nested.extend_from_slice(&buffer[..size]);
            }
        })
        .await
        .unwrap();
        eprintln!(
            "nested supervisor stdout={:?}",
            String::from_utf8_lossy(&nested)
        );
        client.close();
        assert_eq!(original, restored);
        assert!(String::from_utf8_lossy(&output.stdout).contains("__INTEROP_PROBE_READY__"));
        assert!(String::from_utf8_lossy(&nested).contains("__INTEROP_NESTED_READY__"));
    }
    #[tokio::test]
    #[ignore = "requires isolated Android adbd; changes only a fresh owned display lease"]
    async fn real_android_resize_and_close_shell_round_trip() {
        let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
        let client = interop_adb::Client::connect_tcp(
            ("127.0.0.1", port),
            interop_adb::ConnectOptions::default(),
        )
        .await
        .unwrap();
        let before = client
            .shell("wm size", 4096, interop_adb::OperationOptions::default())
            .await
            .unwrap();
        for cancel in [false, true] {
            let owner = uuid::Uuid::new_v4().to_string();
            let resize = quote(&resize(&owner, 920, 1920).unwrap()).unwrap();
            // Kill the resize requester while its already-admitted wm worker is
            // delayed. The supervisor must wait for the real worker, then restore;
            // a late Binder mutation must not revive pixels after close.
            let setup = if cancel {
                let wrapper = quote(
                    r#"#!/system/bin/sh
if [ "$1" = size ] && [ "$2" = 920x1920 ]; then
    kill -KILL "$PPID"
    sleep .2
    /system/bin/wm "$@" || exit "$?"
    /system/bin/wm size >&2
    echo __INTEROP_LATE_WORKER_APPLIED__ >&2
    exit 0
fi
exec /system/bin/wm "$@"
"#,
                )
                .unwrap();
                format!(
                    "mkdir {LEASE}/test-bin && printf '%s' {wrapper} > {LEASE}/test-bin/wm && chmod 700 {LEASE}/test-bin/wm || exit 90\nPATH={LEASE}/test-bin:$PATH\nexport PATH\n"
                )
            } else {
                String::new()
            };
            let expected_status = if cancel { 137 } else { 0 };
            let body = format!(
                r#"{setup}/system/bin/sh -c {resize}
result=$?
echo "__RESIZE_STATUS__$result"
wm size
exit "$result""#
            );
            let script = supervise(&body, &owner, 946, 1920).unwrap();
            let result = client
                .shell(
                    &script,
                    131072,
                    interop_adb::OperationOptions {
                        timeout: std::time::Duration::from_secs(12),
                        ..Default::default()
                    },
                )
                .await;
            let after = client.shell(
            &format!("wm size; if [ -e {LEASE} ] || [ -L {LEASE} ]; then echo __LEASE_REMAINS__; ls -la {LEASE}; fi"),
            8192, interop_adb::OperationOptions::default(),
        ).await.unwrap();
            let late = client
                .shell(
                    &super::resize(&owner, 864, 1920).unwrap(),
                    4096,
                    interop_adb::OperationOptions::default(),
                )
                .await
                .unwrap();
            let after_late = client
                .shell("wm size", 4096, interop_adb::OperationOptions::default())
                .await
                .unwrap();
            let mut evidence = format!(
                "owner={owner} cancel={cancel}\nbefore={}\nafter={}\n",
                String::from_utf8_lossy(&before.stdout),
                String::from_utf8_lossy(&after.stdout)
            );
            if let Ok(receipt) = &result {
                evidence.push_str(&format!(
                    "exit={:?}\nstdout={}\nstderr={}\n",
                    receipt.exit_code,
                    String::from_utf8_lossy(&receipt.stdout),
                    String::from_utf8_lossy(&receipt.stderr)
                ));
            } else {
                evidence.push_str(&format!("request error={result:?}\n"));
            }
            let original = String::from_utf8_lossy(&before.stdout)
                .lines()
                .find_map(|line| line.strip_prefix("Override size: "))
                .unwrap_or("reset")
                .to_owned();
            // Recovery is test-only and guarded by this fresh UUID, no active lock,
            // and the exact recorded target/pending pixels. Preserve observed RED
            // before cleanup; recovery cannot make the assertions pass afterwards.
            let cleanup = format!(
                r#"{READ_SIZE}
lease={LEASE}
if [ -f "$lease/owner" ] && [ ! -e "$lease/busy" ] && [ ! -L "$lease/busy" ]; then
 IFS= read -r owner < "$lease/owner"
 IFS= read -r target < "$lease/target"
 pending=; if [ -f "$lease/pending" ]; then IFS= read -r pending < "$lease/pending"; fi
 if [ "$owner" = {} ] && read_override && {{ [ "$override" = "$target" ] || [ "$override" = "$pending" ]; }}; then
  wm size {} && rm -rf -- "$lease"
 fi
fi"#,
                quote(&owner).unwrap(),
                quote(&original).unwrap()
            );
            let cleanup = client
                .shell(&cleanup, 4096, interop_adb::OperationOptions::default())
                .await;
            evidence.push_str(&format!(
                "late_exit={:?}\nafter_late={}\ncleanup={cleanup:?}\n",
                late.exit_code,
                String::from_utf8_lossy(&after_late.stdout)
            ));
            let path = std::env::temp_dir().join(format!("scrcpy-display-round-trip-{owner}.log"));
            std::fs::write(&path, &evidence).unwrap();
            eprintln!("{evidence}\nEvidence: {}", path.display());
            let result = result.unwrap();
            assert_eq!(result.exit_code, Some(expected_status));
            if cancel {
                let stderr = String::from_utf8_lossy(&result.stderr);
                assert!(
                    stderr.contains("__INTEROP_LATE_WORKER_APPLIED__"),
                    "late wm was not exercised: {stderr}"
                );
                assert!(
                    stderr.contains("Override size: 920x1920"),
                    "late wm did not apply: {stderr}"
                );
            }
            assert!(
                String::from_utf8_lossy(&result.stdout)
                    .contains(&format!("__RESIZE_STATUS__{expected_status}"))
            );
            assert_eq!(
                after.stdout, before.stdout,
                "owned override or lease was not restored"
            );
            assert_eq!(
                late.exit_code,
                Some(41),
                "late resize was admitted after close"
            );
            assert_eq!(
                after_late.stdout, before.stdout,
                "late resize revived the override"
            );
        }
        client.close();
    }

    #[test]
    fn virtual_dimensions_accept_scaled_pixels_without_relaxing_physical_overrides() {
        assert_eq!(virtual_dimensions(&json!({})).unwrap(), None);
        for (width, height) in [(64, 320), (144, 720), (2, 4096), (4096, 2), (3, 5)] {
            let params = json!({"displayWidth":width,"displayHeight":height});
            assert_eq!(virtual_dimensions(&params).unwrap(), Some((width, height)));
            assert_eq!(dimensions(&params).unwrap_err().code, "invalid_argument");
        }
        for params in [
            json!({"displayWidth":0,"displayHeight":320}),
            json!({"displayWidth":320,"displayHeight":1}),
            json!({"displayWidth":4097,"displayHeight":320}),
            json!({"displayWidth":320,"displayHeight":4097}),
            json!({"displayWidth":64}),
            json!({"displayHeight":320}),
            json!({"displayWidth":"64","displayHeight":320}),
            json!({"displayWidth":64,"displayHeight":null}),
        ] {
            assert_eq!(
                virtual_dimensions(&params).unwrap_err().code,
                "invalid_argument"
            );
        }
    }

    #[cfg(unix)]
    fn fixture() -> (tempfile::TempDir, std::path::PathBuf) {
        use std::os::unix::fs::PermissionsExt;
        let root = tempfile::tempdir().unwrap();
        let wm = root.path().join("wm");
        std::fs::write(
            &wm,
            r#"#!/bin/sh
if [ "$#" = 1 ]; then
    echo 'Physical size: 1080x2400'
    value=$(cat "$DISPLAY_FIXTURE/size")
    if [ "$value" != reset ]; then echo "Override size: $value"; fi
elif [ "$2" = 800x800 ]; then
    exit 1
else
    echo "$2" > "$DISPLAY_FIXTURE/size"
fi
"#,
        )
        .unwrap();
        std::fs::set_permissions(&wm, std::fs::Permissions::from_mode(0o755)).unwrap();
        let lease = root.path().join("lease");
        std::fs::write(root.path().join("dumpsys"), "#!/bin/sh\necho 'Viewport INTERNAL: displayId=0, orientation='\"${DISPLAY_ROTATION:-0}\"', logicalFrame=[]'\n").unwrap();
        std::fs::set_permissions(
            root.path().join("dumpsys"),
            std::fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        (root, lease)
    }

    #[cfg(unix)]
    fn run(root: &std::path::Path, lease: &std::path::Path, source: &str) -> std::process::Output {
        std::process::Command::new("/bin/sh")
            .args([
                "-c",
                &source
                    .replace(LEASE, lease.to_str().unwrap())
                    .replace("/system/bin/sh", "/bin/sh"),
            ])
            .env("DISPLAY_FIXTURE", root)
            .env("PATH", format!("{}:/usr/bin:/bin", root.display()))
            .output()
            .unwrap()
    }

    #[test]
    #[cfg(unix)]
    fn supervisor_restores_preexisting_override_and_preserves_outside_edits() {
        let (root, lease) = fixture();
        for (initial, body, expected) in [
            ("reset", "true", "reset"),
            ("1000x2000", "true", "1000x2000"),
            ("1000x2000", "wm size 600x900", "600x900"),
        ] {
            std::fs::write(root.path().join("size"), initial).unwrap();
            let output = run(
                root.path(),
                &lease,
                &supervise(body, "owner", 1080, 1920).unwrap(),
            );
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(
                std::fs::read_to_string(root.path().join("size"))
                    .unwrap()
                    .trim(),
                expected
            );
            assert!(!lease.exists());
        }
    }

    #[test]
    #[cfg(unix)]
    fn lock_publication_needs_no_hard_links_and_preserves_existing_entries() {
        use std::os::unix::fs::{PermissionsExt, symlink};
        let (root, lease) = fixture();
        // Android SELinux denies the hard-link form even within shell-owned
        // /data/local/tmp. The fixture rejects it instead of hiding that seam.
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let ln = root.path().join("ln");
        std::fs::write(
            &ln,
            "#!/bin/sh\n[ \"$1\" = -s ] || exit 77\nexec /bin/ln \"$@\"\n",
        )
        .unwrap();
        std::fs::set_permissions(&ln, std::fs::Permissions::from_mode(0o755)).unwrap();
        let request = quote(&resize("owner", 920, 1920).unwrap()).unwrap();
        let body = format!("/system/bin/sh -c {request}");
        let output = run(
            root.path(),
            &lease,
            &supervise(&body, "owner", 946, 1920).unwrap(),
        );
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!lease.exists());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );

        std::fs::create_dir(&lease).unwrap();
        std::fs::write(lease.join("owner"), "owner\n").unwrap();
        std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
        std::fs::write(lease.join("original"), "reset\n").unwrap();
        std::fs::write(root.path().join("size"), "1080x1920").unwrap();
        for kind in ["file", "directory", "dangling", "directory-symlink"] {
            let busy = lease.join("busy");
            let outside = root.path().join("outside");
            match kind {
                "file" => std::fs::write(&busy, "other-lock\n").unwrap(),
                "directory" => std::fs::create_dir(&busy).unwrap(),
                "dangling" => symlink(root.path().join("absent"), &busy).unwrap(),
                _ => {
                    std::fs::create_dir(&outside).unwrap();
                    symlink(&outside, &busy).unwrap();
                }
            }
            let output = run(root.path(), &lease, &resize("owner", 920, 1920).unwrap());
            assert!(!output.status.success(), "replaced {kind}");
            assert!(std::fs::symlink_metadata(&busy).is_ok(), "removed {kind}");
            if kind == "file" {
                assert_eq!(std::fs::read_to_string(&busy).unwrap(), "other-lock\n");
            }
            if kind == "directory" {
                assert_eq!(std::fs::read_dir(&busy).unwrap().count(), 0);
                std::fs::remove_dir(&busy).unwrap();
            } else {
                std::fs::remove_file(&busy).unwrap();
            }
            if kind == "directory-symlink" {
                assert_eq!(std::fs::read_dir(&outside).unwrap().count(), 0);
            }
            assert_eq!(
                std::fs::read_to_string(root.path().join("size"))
                    .unwrap()
                    .trim(),
                "1080x1920"
            );
        }
    }

    #[test]
    #[cfg(unix)]
    fn failed_resize_preserves_the_owned_target_for_later_restoration() {
        let (root, lease) = fixture();
        std::fs::create_dir(&lease).unwrap();
        std::fs::write(root.path().join("size"), "1080x1920").unwrap();
        std::fs::write(lease.join("owner"), "owner\n").unwrap();
        std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
        std::fs::write(lease.join("original"), "reset\n").unwrap();
        let output = run(root.path(), &lease, &resize("owner", 800, 800).unwrap());
        assert!(!output.status.success());
        assert_eq!(
            std::fs::read_to_string(lease.join("target"))
                .unwrap()
                .trim(),
            "1080x1920"
        );
        assert!(!lease.join("busy").exists());
        // Closing fences new requests; only the already-owned operation or
        // its supervisor may restore the old capture's lease.
        std::fs::write(lease.join("closing-owner"), "").unwrap();
        let output = run(root.path(), &lease, &resize("owner", 1000, 2000).unwrap());
        assert!(!output.status.success());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "1080x1920"
        );
        assert!(!lease.join("busy").exists());
    }

    #[test]
    #[cfg(unix)]
    fn cancelled_resize_releases_lock_and_restores_when_closing() {
        for signal in ["HUP", "INT", "TERM", "USR1"] {
            for outside in [false, true] {
                let (root, lease) = fixture();
                std::fs::create_dir(&lease).unwrap();
                std::fs::write(root.path().join("size"), "1080x1920").unwrap();
                std::fs::write(lease.join("owner"), "owner\n").unwrap();
                std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
                std::fs::write(lease.join("original"), "reset\n").unwrap();
                let wm = root.path().join("wm");
                let edit = if outside {
                    "echo 600x900 > \"$DISPLAY_FIXTURE/size\";"
                } else {
                    ""
                };
                let script = std::fs::read_to_string(&wm).unwrap().replace(
                    "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"",
                    &format!("echo \"$2\" > \"$DISPLAY_FIXTURE/size\"\nif [ \"$2\" = 864x1920 ]; then touch \"$DISPLAY_FIXTURE/lease/closing-owner\"; {edit} kill -{signal} \"$PPID\"; fi"),
                );
                std::fs::write(wm, script).unwrap();
                let output = run(root.path(), &lease, &resize("owner", 864, 1920).unwrap());
                assert!(
                    !output.status.success(),
                    "cancellation must remain visible: {signal}"
                );
                assert!(!lease.exists(), "{signal} orphaned its busy/closing lease");
                assert_eq!(
                    std::fs::read_to_string(root.path().join("size"))
                        .unwrap()
                        .trim(),
                    if outside { "600x900" } else { "reset" }
                );
            }
        }
    }

    #[test]
    #[cfg(unix)]
    fn supervisor_reaps_a_killed_resize_and_restores_uncommitted_pixels() {
        for kill_before_apply in [false, true] {
            let (root, lease) = fixture();
            std::fs::write(root.path().join("size"), "reset").unwrap();
            let wm = root.path().join("wm");
            let mutation = if kill_before_apply {
                // The requesting shell is already dead while the actual wm
                // worker still has a pending system operation. Restoring before
                // that worker exits would let its late write resurrect pixels.
                "if [ \"$2\" = 864x1920 ]; then touch \"$DISPLAY_FIXTURE/applied\"; kill -KILL \"$PPID\"; sleep .2; fi\necho \"$2\" > \"$DISPLAY_FIXTURE/size\""
            } else {
                "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"\nif [ \"$2\" = 864x1920 ]; then touch \"$DISPLAY_FIXTURE/applied\"; kill -KILL \"$PPID\"; fi"
            };
            let script = std::fs::read_to_string(&wm)
                .unwrap()
                .replace("echo \"$2\" > \"$DISPLAY_FIXTURE/size\"", mutation);
            std::fs::write(wm, script).unwrap();
            let request = quote(&resize("owner", 864, 1920).unwrap()).unwrap();
            let body = format!(
                r#"/system/bin/sh -c {request} > "$DISPLAY_FIXTURE/resize-log" 2>&1 &
while [ ! -f "$DISPLAY_FIXTURE/applied" ]; do sleep .01; done
sleep .05"#
            );
            let output = run(
                root.path(),
                &lease,
                &supervise(&body, "owner", 1080, 1920).unwrap(),
            );
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(!lease.exists(), "supervisor abandoned a dead resize owner");
            assert_eq!(
                std::fs::read_to_string(root.path().join("size"))
                    .unwrap()
                    .trim(),
                "reset"
            );
        }
    }

    #[test]
    #[cfg(unix)]
    fn cancelled_resize_without_close_retains_confirmed_pixels_for_its_owner() {
        let (root, lease) = fixture();
        std::fs::create_dir(&lease).unwrap();
        std::fs::write(root.path().join("size"), "1080x1920").unwrap();
        std::fs::write(lease.join("owner"), "owner\n").unwrap();
        std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
        std::fs::write(lease.join("original"), "reset\n").unwrap();
        let wm = root.path().join("wm");
        let script = std::fs::read_to_string(&wm).unwrap().replace(
            "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"",
            "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"\nif [ \"$2\" = 864x1920 ]; then kill -HUP \"$PPID\"; fi",
        );
        std::fs::write(wm, script).unwrap();
        let output = run(root.path(), &lease, &resize("owner", 864, 1920).unwrap());
        assert!(!output.status.success());
        assert!(!lease.join("busy").exists());
        assert_eq!(
            std::fs::read_to_string(lease.join("target"))
                .unwrap()
                .trim(),
            "864x1920"
        );
        let close = format!(
            "{READ_SIZE}\nlease={LEASE}\nlease_owner=owner\n{LEASE_LOCK}\nprepare_lock && try_lock && restore_owned"
        );
        assert!(run(root.path(), &lease, &close).status.success());
        assert!(!lease.exists());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );
        assert!(!run(root.path(), &lease, &close).status.success());
        assert!(!lease.exists(), "repeated close recreated a retired lease");
    }

    #[test]
    #[cfg(unix)]
    fn closing_supervisor_keeps_ownership_until_live_resize_finishes() {
        use std::time::{Duration, Instant};
        let (root, lease) = fixture();
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let wm = root.path().join("wm");
        let script = std::fs::read_to_string(&wm).unwrap().replace(
            "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"",
            "echo \"$2\" > \"$DISPLAY_FIXTURE/size\"\nif [ \"$2\" = 864x1920 ]; then touch \"$DISPLAY_FIXTURE/applied\"; while [ ! -f \"$DISPLAY_FIXTURE/release\" ]; do sleep .01; done; fi",
        );
        std::fs::write(wm, script).unwrap();
        let request = quote(&resize("owner", 864, 1920).unwrap()).unwrap();
        let body = format!(
            r#"/system/bin/sh -c {request} > "$DISPLAY_FIXTURE/resize-log" 2>&1 &
while [ ! -f "$DISPLAY_FIXTURE/applied" ]; do sleep .01; done"#
        );
        let source = supervise(&body, "owner", 1080, 1920)
            .unwrap()
            .replace(LEASE, lease.to_str().unwrap())
            .replace("/system/bin/sh", "/bin/sh");
        let mut child = std::process::Command::new("/bin/sh")
            .args(["-c", &source])
            .env("DISPLAY_FIXTURE", root.path())
            .env("PATH", format!("{}:/usr/bin:/bin", root.path().display()))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while !lease.join("closing-owner").exists() && Instant::now() < deadline {
            if child.try_wait().unwrap().is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        std::thread::sleep(Duration::from_millis(3200));
        let abandoned = child.try_wait().unwrap();
        // Release even on regression so a failed test cannot leave its fixture.
        std::fs::write(root.path().join("release"), "").unwrap();
        let output = child.wait_with_output().unwrap();
        assert!(
            abandoned.is_none(),
            "supervisor abandoned a still-live resize"
        );
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!lease.exists());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );
    }

    #[test]
    #[cfg(unix)]
    fn failed_restoration_read_preserves_unconfirmed_lease_instead_of_claiming_cleanup() {
        let (root, lease) = fixture();
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let wm = root.path().join("wm");
        let script = std::fs::read_to_string(&wm).unwrap().replace(
            "if [ \"$#\" = 1 ]; then",
            "if [ \"$#\" = 1 ]; then\n    [ ! -f \"$DISPLAY_FIXTURE/read-fails\" ] || exit 1",
        );
        std::fs::write(wm, script).unwrap();
        let output = run(
            root.path(),
            &lease,
            &supervise("touch \"$DISPLAY_FIXTURE/read-fails\"", "owner", 1080, 1920).unwrap(),
        );
        assert!(!output.status.success());
        assert!(
            lease.exists(),
            "unconfirmed restoration discarded its owner"
        );
        assert!(!lease.join("busy").exists());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "1080x1920"
        );
        assert_eq!(
            std::fs::read_to_string(lease.join("original"))
                .unwrap()
                .trim(),
            "reset"
        );
    }

    #[test]
    #[cfg(unix)]
    fn reused_pid_does_not_keep_a_dead_capture_lock_alive() {
        let (root, lease) = fixture();
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let body = format!(
            r#"printf '%s\n' '{}:0:owner' > '{LEASE}/busy'"#,
            std::process::id()
        );
        let output = run(
            root.path(),
            &lease,
            &supervise(&body, "owner", 1080, 1920).unwrap(),
        );
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!lease.exists());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );
    }

    #[test]
    #[cfg(unix)]
    fn late_resize_after_close_cannot_change_or_recreate_the_override() {
        let (root, lease) = fixture();
        std::fs::create_dir(&lease).unwrap();
        std::fs::write(root.path().join("size"), "1080x1920").unwrap();
        std::fs::write(lease.join("owner"), "owner\n").unwrap();
        std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
        std::fs::write(lease.join("original"), "reset\n").unwrap();
        std::fs::write(lease.join("closing-owner"), "").unwrap();
        let output = run(root.path(), &lease, &resize("owner", 864, 1920).unwrap());
        assert!(
            !output.status.success(),
            "a closing lease accepted a new resize"
        );
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "1080x1920"
        );
        assert!(!lease.join("busy").exists());
        // The actual owner finishes close before this still-later request.
        std::fs::remove_dir_all(&lease).unwrap();
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let output = run(root.path(), &lease, &resize("owner", 864, 1920).unwrap());
        assert!(!output.status.success());
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );
        assert!(!lease.exists());
    }

    #[test]
    #[cfg(unix)]
    fn another_window_cannot_resize_or_restore_the_owned_display() {
        let (root, lease) = fixture();
        std::fs::create_dir(&lease).unwrap();
        std::fs::write(root.path().join("size"), "1080x1920").unwrap();
        std::fs::write(lease.join("owner"), "current\n").unwrap();
        std::fs::write(lease.join("target"), "1080x1920\n").unwrap();
        assert!(
            !run(root.path(), &lease, &resize("stale", 1000, 2000).unwrap())
                .status
                .success()
        );
        assert!(
            !run(
                root.path(),
                &lease,
                &supervise("true", "stale", 1000, 2000).unwrap()
            )
            .status
            .success()
        );
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "1080x1920"
        );
        assert_eq!(
            std::fs::read_to_string(lease.join("owner")).unwrap().trim(),
            "current"
        );
    }

    #[test]
    #[cfg(unix)]
    fn rotated_primary_display_uses_natural_dimensions_and_restores_original() {
        let (root, lease) = fixture();
        std::fs::write(root.path().join("size"), "reset").unwrap();
        let source = format!(
            "export DISPLAY_ROTATION=1\n{}",
            supervise("cat \"$DISPLAY_FIXTURE/size\"", "owner", 1920, 1080).unwrap()
        );
        let output = run(root.path(), &lease, &source);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "1080x1920");
        assert_eq!(
            std::fs::read_to_string(root.path().join("size"))
                .unwrap()
                .trim(),
            "reset"
        );
    }
}
