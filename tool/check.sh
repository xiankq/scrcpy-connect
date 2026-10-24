#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart tool/check_architecture.dart
case "$(uname -s)" in
  Linux*) dart packages/adb/tool/prepare_adb.dart --platform linux ;;
  Darwin*) dart packages/adb/tool/prepare_adb.dart --platform macos ;;
esac
npm ci --ignore-scripts --prefix tool/design_tokens
dart tool/protocol_codegen.dart --check
dart tool/generate.dart --check
dart servers/vendor/build.dart --check
dart servers/companion/build.dart --check
dart servers/helpers/build.dart --check
dart servers/package.dart --check
dart servers/companion/tests/compatibility.dart
dart servers/tests/tooling_test.dart
dart servers/tests/package_test.dart
flutter test --no-pub tool/test tool/e2e/tests
dart tool/driver/support/android_screencap_test.dart
dart tool/driver/support/adb_fault_proxy_tcp_test.dart
npm test --prefix tool/design_tokens
dart format --output=none --set-exit-if-changed app/lib app/test app/integration_test tool servers packages
cargo fmt --all --check
cargo fmt --manifest-path rust/media_codec/Cargo.toml --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
# 被控助手独立于宿主 workspace；Linux 夹具验证原始路径字节与元数据语义。
if [[ "$(uname -s)" == Linux* ]]; then
  cargo fmt --manifest-path rust/adb/device_fs_helper/Cargo.toml --check
  cargo clippy --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml --all-targets -- -D warnings
  cargo test --locked --manifest-path rust/adb/device_fs_helper/Cargo.toml
fi
flutter analyze --no-pub --fatal-infos
dart tool/check_analyzer_plugin.dart
(cd app && flutter test --no-pub)
(cd packages/design_system && flutter test --no-pub)
for capability in adb scrcpy media_codec; do
  (cd "packages/$capability" && flutter test --no-pub)
done
npm run lint --prefix tool/design_tokens
if [[ "${1:-}" == "--android" ]]; then
  (cd app && flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64)
  dart tool/check_android.dart app/build/app/outputs/flutter-apk/app-debug.apk
  # 这些是 JVM main 入口，Gradle 的 testDebugUnitTest 不会执行它们。
  dart tool/native_contracts.dart
fi
