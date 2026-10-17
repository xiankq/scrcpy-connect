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
  (cd apps/connect && flutter build apk --debug --no-pub --target-platform android-arm64,android-x64)
fi
