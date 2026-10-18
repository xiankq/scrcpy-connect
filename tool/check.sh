#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
npm ci --ignore-scripts --prefix tool/design_tokens
python3 tool/protocol_codegen.py --check
python3 tool/generate.py --check
python3 servers/companion/build.py --check
python3 -m unittest discover -s tool -p 'test_*.py'
npm test --prefix tool/design_tokens
python3 tool/check_native_deps.py
dart format --output=none --set-exit-if-changed lib test integration_test test_driver packages
cargo fmt --all --check
python3 tool/fvp_snapshot_regression.py
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
flutter analyze --no-pub --fatal-infos
python3 tool/check_analyzer_plugin.py
flutter test --no-pub
(cd packages/design_system && flutter test --no-pub)
dart --disable-dart-dev --packages=.dart_tool/package_config.json test_driver/integration_test_contract_test.dart
(cd packages/interop_bridge && flutter test --no-pub)
npm run lint --prefix tool/design_tokens
if [[ "${1:-}" == "--android" ]]; then
  flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64
  python3 tool/android.py verify build/app/outputs/flutter-apk/app-debug.apk
  # These Kotlin tests have JVM main entrypoints, not JUnit annotations;
  # Gradle's testDebugUnitTest alone does not execute their assertions.
  python3 android/app/src/test/run_native_ownership_tests.py
  python3 android/app/src/test/run_audio_contract_tests.py
  python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

apk = Path("build/app/outputs/flutter-apk/app-debug.apk")
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
