#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart --disable-dart-dev scripts/check_test_budget.dart
dart --disable-dart-dev scripts/check_architecture.dart
case "$(uname -s)" in
  Linux*)
    dart --disable-dart-dev packages/adb/tool/prepare_adb.dart --platform linux
    export INTEROP_OFFICIAL_ADB_BINARY="$PWD/.dart_tool/adb/linux/adb"
    ;;
  Darwin*)
    dart --disable-dart-dev packages/adb/tool/prepare_adb.dart --platform macos
    export INTEROP_OFFICIAL_ADB_BINARY="$PWD/.dart_tool/adb/macos/adb"
    ;;
esac
npm ci --ignore-scripts --prefix scripts/design_tokens
dart --disable-dart-dev scripts/protocol_codegen.dart --check
dart --disable-dart-dev servers/build.dart --check vendor companion helpers
dart --disable-dart-dev scripts/generate.dart --check
dart --disable-dart-dev servers/companion/tests/compatibility.dart
dart --disable-dart-dev servers/tests/tooling_test.dart
dart --disable-dart-dev servers/tests/package_test.dart
(cd test/host && dart pub get --enforce-lockfile && dart analyze --fatal-infos && dart test)
dart --disable-dart-dev test/host/checks/adb_fault_proxy_tcp_test.dart
npm test --prefix scripts/design_tokens
dart format --output=none --set-exit-if-changed app/lib app/test app/integration_test test scripts servers packages
cargo fmt --all --check
cargo fmt --manifest-path rust/media_codec/Cargo.toml --check
PYTHONPATH=packages/media_codec/tool python3 -B -m unittest discover -s packages/media_codec/test/tool -p 'test_*.py'
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
# 媒体核心是独立 workspace；生成检查已要求对应宿主的固定 FFmpeg 缓存。
media_rust_target="${CARGO_TARGET_DIR:-$PWD/.dart_tool/media_codec/rust-target}"
(
  export MEDIA_CODEC_FFMPEG_ROOT="${MEDIA_CODEC_FFMPEG_ROOT:-$(python3 - <<'PY_HOST'
import platform
from pathlib import Path
host = {"Linux": "linux", "Darwin": "macos", "Windows": "windows"}[platform.system()]
arch = {"x86_64": "x64", "amd64": "x64", "aarch64": "arm64", "arm64": "arm64"}[platform.machine().lower()]
print(Path(".dart_tool/media_codec/ffmpeg", f"{host}-{arch}").resolve())
PY_HOST
)}"
  export CARGO_TARGET_DIR="$media_rust_target"
  cargo clippy --locked --manifest-path rust/media_codec/Cargo.toml --all-targets -- -D warnings
  cargo test --locked --manifest-path rust/media_codec/Cargo.toml
)
case "$(uname -s)" in
  Linux*) media_native_library=libmedia_codec_native.so ;;
  Darwin*) media_native_library=libmedia_codec_native.dylib ;;
  *) media_native_library=media_codec_native.dll ;;
esac
export MEDIA_CODEC_TEST_LIBRARY="${MEDIA_CODEC_TEST_LIBRARY:-$media_rust_target/debug/deps/$media_native_library}"
# 被控助手独立于宿主 workspace；Linux 夹具验证原始路径字节与元数据语义。
if [[ "$(uname -s)" == Linux* ]]; then
  cargo fmt --manifest-path rust/adb/device_fs_helper/Cargo.toml --check
  cargo clippy --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml --all-targets -- -D warnings
  cargo test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
fi
flutter analyze --no-pub --fatal-infos
dart --disable-dart-dev test/analyzer_plugin.dart
test_report="$(mktemp)"
trap 'rm -f "$test_report"' EXIT
(cd app && flutter test --no-pub --file-reporter="json:$test_report")
dart --disable-dart-dev scripts/check_test_budget.dart --runtime app/host "$test_report"
(cd packages/design_system && flutter test --no-pub --file-reporter="json:$test_report")
dart --disable-dart-dev scripts/check_test_budget.dart --runtime packages/design_system "$test_report"
for capability in adb scrcpy media_codec; do
  (cd "packages/$capability" && flutter test --no-pub --file-reporter="json:$test_report")
  dart --disable-dart-dev scripts/check_test_budget.dart --runtime "packages/$capability" "$test_report"
done
npm run lint --prefix scripts/design_tokens
if [[ "${1:-}" == "--android" ]]; then
  # 调试只构建当次宿主 ABI；跨 ABI 交付检查由发布构建负责。
  android_target="${ANDROID_TARGET_PLATFORM:-android-arm64}"
  case "$android_target" in
    android-arm) android_abi=armeabi-v7a ;;
    android-arm64) android_abi=arm64-v8a ;;
    android-x64) android_abi=x86_64 ;;
    *) echo "Unsupported ANDROID_TARGET_PLATFORM: $android_target" >&2; exit 2 ;;
  esac
  (cd app && flutter build apk --debug --no-pub --target-platform "$android_target")
  dart --disable-dart-dev scripts/android.dart verify app/build/app/outputs/flutter-apk/app-debug.apk --abis="$android_abi"
  # 这些是 JVM main 入口，Gradle 的 testDebugUnitTest 不会执行它们。
  dart --disable-dart-dev test/native_contracts.dart
fi
