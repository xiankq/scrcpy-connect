#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
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
npm test --prefix tool/design_tokens
dart format --output=none --set-exit-if-changed app/lib app/test app/integration_test tool servers packages
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
flutter analyze --no-pub --fatal-infos
dart tool/check_analyzer_plugin.dart
(cd app && flutter test --no-pub)
(cd packages/design_system && flutter test --no-pub)
(cd packages/interop_bridge && flutter test --no-pub)
npm run lint --prefix tool/design_tokens
if [[ "${1:-}" == "--android" ]]; then
  (cd app && flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64)
  dart tool/check_android.dart app/build/app/outputs/flutter-apk/app-debug.apk
  # These are JVM main entrypoints; Gradle's testDebugUnitTest does not run them.
  dart tool/native_contracts.dart
fi
