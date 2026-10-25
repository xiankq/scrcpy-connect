#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart --disable-dart-dev tool/check_test_budget.dart
dart --disable-dart-dev tool/check_architecture.dart
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
npm ci --ignore-scripts --prefix tool/design_tokens
dart --disable-dart-dev tool/protocol_codegen.dart --check
dart --disable-dart-dev tool/generate.dart --check
dart --disable-dart-dev servers/vendor/build.dart --check
dart --disable-dart-dev servers/companion/build.dart --check
dart --disable-dart-dev servers/helpers/build.dart --check
dart --disable-dart-dev servers/companion/tests/compatibility.dart
dart --disable-dart-dev servers/tests/tooling_test.dart
dart --disable-dart-dev servers/tests/package_test.dart
(cd tool/host && dart pub get --enforce-lockfile && dart analyze --fatal-infos && dart test test e2e_test)
dart --disable-dart-dev tool/driver/support/adb_fault_proxy_tcp_test.dart
npm test --prefix tool/design_tokens
dart format --output=none --set-exit-if-changed app/lib app/test app/integration_test tool servers packages
cargo fmt --all --check
cargo fmt --manifest-path rust/media_codec/Cargo.toml --check
(cd packages/media_codec/tool && python3 -B -m unittest test_build_ffmpeg.py)
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
# 被控助手独立于宿主 workspace；Linux 夹具验证原始路径字节与元数据语义。
if [[ "$(uname -s)" == Linux* ]]; then
  cargo fmt --manifest-path rust/adb/device_fs_helper/Cargo.toml --check
  cargo clippy --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml --all-targets -- -D warnings
  cargo test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
fi
flutter analyze --no-pub --fatal-infos
dart --disable-dart-dev tool/check_analyzer_plugin.dart
(cd app && flutter test --no-pub)
(cd packages/design_system && flutter test --no-pub)
for capability in adb scrcpy media_codec; do
  (cd "packages/$capability" && flutter test --no-pub)
done
npm run lint --prefix tool/design_tokens
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
  dart --disable-dart-dev tool/check_android.dart app/build/app/outputs/flutter-apk/app-debug.apk --abis="$android_abi"
  # 这些是 JVM main 入口，Gradle 的 testDebugUnitTest 不会执行它们。
  dart --disable-dart-dev tool/native_contracts.dart
fi
