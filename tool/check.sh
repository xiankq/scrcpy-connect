#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
python3 tool/generate.py --check
dart format --output=none --set-exit-if-changed apps/connect/lib apps/connect/test apps/connect/integration_test apps/connect/test_driver packages
cargo fmt --all --check
python3 servers/scrcpy/build.py --check
python3 servers/scrcpy/test.py
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
flutter analyze --no-pub --fatal-infos
python3 tool/check_analyzer_plugin.py
(cd apps/connect && flutter test --no-pub)
(cd packages/design_system && flutter test --no-pub)
dart --disable-dart-dev --packages=.dart_tool/package_config.json apps/connect/test_driver/integration_test_contract_test.dart
(cd packages/interop_bridge && flutter test --no-pub)
npx --yes --package=@google/design.md@0.4.0 designmd lint designs/design.md
if [[ "${1:-}" == "--android" ]]; then
  (cd apps/connect && flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64)
  # These Kotlin tests have JVM main entrypoints, not JUnit annotations;
  # Gradle's testDebugUnitTest alone does not execute their assertions.
  python3 apps/connect/android/app/src/test/run_native_ownership_tests.py
  python3 apps/connect/android/app/src/test/run_audio_contract_tests.py
  python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

apk = Path("apps/connect/build/app/outputs/flutter-apk/app-debug.apk")
with zipfile.ZipFile(apk) as archive:
    # Check the packaged binaries, including ELF architecture, rather than
    # trusting the Flutter target-platform argument or build intermediates.
    for abi, elf_class, machine in (
        ("armeabi-v7a", 1, 40),
        ("arm64-v8a", 2, 183),
        ("x86_64", 2, 62),
    ):
        for library in ("libflutter.so", "libinterop_bridge.so"):
            name = f"lib/{abi}/{library}"
            with archive.open(name) as binary:
                header = binary.read(20)
            if (header[:4] != b"\x7fELF" or len(header) < 20
                    or header[4] != elf_class or header[5] != 1
                    or int.from_bytes(header[18:20], "little") != machine):
                raise SystemExit(f"Invalid packaged ELF architecture: {name}")

sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
analyzer = sdk / "cmdline-tools/latest/bin/apkanalyzer"
manifest = ET.fromstring(subprocess.check_output(
    [str(analyzer), "manifest", "print", str(apk)], text=True))
android = "{http://schemas.android.com/apk/res/android}"
application = manifest.find("application")
if application is None:
    raise SystemExit("Packaged manifest is missing its application")
for attribute in ("allowBackup", "usesCleartextTraffic"):
    if application.get(android + attribute) != "false":
        raise SystemExit(f"Packaged manifest must disable {attribute}")
activity = next((item for item in application.findall("activity")
                 if item.get(android + "name", "").endswith(".MainActivity")), None)
# apkanalyzer can print compiled enums as numeric values instead of names.
# ActivityInfo.LAUNCH_SINGLE_TASK = 2 (verified against the pinned SDK).
if activity is None or activity.get(android + "launchMode") not in {"singleTask", "2", "0x2"}:
    raise SystemExit("Packaged MainActivity must use singleTask")
service = next((item for item in application.findall("service")
                if item.get(android + "name", "").endswith(".ConnectionService")), None)
types = service.get(android + "foregroundServiceType", "") if service is not None else ""
# ServiceInfo: connectedDevice (0x10) | mediaPlayback (0x2).
if (service is None or service.get(android + "exported") != "false"
        or (types not in {"18", "0x12"}
            and set(types.split("|")) != {"connectedDevice", "mediaPlayback"})):
    raise SystemExit("Packaged ConnectionService must retain its private foreground types")
print("PASS: packaged Android manifest and Flutter/Rust ELF libraries for all three ABIs")
PY
fi
