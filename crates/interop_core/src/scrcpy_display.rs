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

/// A device-side lease follows the supervised process, including host EOF.
/// Exclusive mkdir prevents another window from taking an override whose
/// original value belongs to this process. Never restore over an outside edit.
pub(super) fn supervise(command: &str, owner: &str, width: u16, height: u16) -> CoreResult<String> {
    let owner = quote(owner)?;
    let command = quote(command)?;
    Ok(format!(
        r#"{READ_SIZE}
{READ_ROTATION}
desired_width={width}
desired_height={height}
read_rotation || {{ echo 'main display rotation could not be verified' >&2; exit 44; }}
lease={LEASE}
mkdir "$lease" 2>/dev/null || {{ echo 'display override already owned by another session' >&2; exit 41; }}
echo {owner} > "$lease/owner"
read_override || {{ rm -rf -- "$lease"; exit 42; }}
original=$override
echo "$original" > "$lease/original"
echo "$natural_size" > "$lease/target"
restore_display() {{
    result=$?
    trap - EXIT
    trap '' HUP INT TERM USR1
    # An in-flight resize inherits restoration if it outlives this supervisor.
    : > "$lease/closing"
    count=0
    while ! mkdir "$lease/busy" 2>/dev/null; do
        count=$((count + 1))
        [ "$count" -lt 30 ] || exit "$result"
        sleep .1
    done
    IFS= read -r current_owner < "$lease/owner"
    IFS= read -r target < "$lease/target"
    if [ "$current_owner" = {owner} ]; then
        if read_override && [ "$override" = "$target" ]; then
            wm size "$original" >&2
        fi
        rm -rf -- "$lease"
    else
        rmdir "$lease/busy" 2>/dev/null
    fi
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
    let owner = quote(owner)?;
    Ok(format!(
        r#"{READ_SIZE}
{READ_ROTATION}
desired_width={width}
desired_height={height}
read_rotation || exit 44
lease={LEASE}
mkdir "$lease/busy" 2>/dev/null || exit 41
finish_resize() {{
    result=$?
    trap - EXIT
    if [ -f "$lease/closing" ]; then
        IFS= read -r current_owner < "$lease/owner"
        IFS= read -r target < "$lease/target"
        IFS= read -r original < "$lease/original"
        if [ "$current_owner" = {owner} ]; then
            if read_override && [ "$override" = "$target" ]; then wm size "$original" >&2; fi
            rm -rf -- "$lease"
        else
            rmdir "$lease/busy" 2>/dev/null
        fi
    else
        rmdir "$lease/busy" 2>/dev/null
    fi
    exit "$result"
}}
trap finish_resize EXIT
IFS= read -r current_owner < "$lease/owner"
[ "$current_owner" = {owner} ] || exit 41
IFS= read -r target < "$lease/target"
read_override && [ "$override" = "$target" ] || exit 42
wm size "$natural_size"
# A failed request may have changed the display. Record confirmed ownership
# before reporting failure, while the operation lock excludes restoration.
read_override || exit 43
[ "$override" = "$natural_size" ] || exit 43
echo "$natural_size" > "$lease/target"
echo __INTEROP_DISPLAY_READY__"#
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
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
        // When the supervisor has already left, the resize owns restoration.
        std::fs::write(lease.join("closing"), "").unwrap();
        let output = run(root.path(), &lease, &resize("owner", 1000, 2000).unwrap());
        assert!(output.status.success());
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
