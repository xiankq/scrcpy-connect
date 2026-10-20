#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
java_bin="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}/bin"
build_dir="$(mktemp -d)"
trap 'rm -rf -- "$build_dir"' EXIT
mkdir -p "$build_dir/classes" "$build_dir/dex"
# Compile the same bounded production source directory needed by Main, plus
# this explicit fixture entry point. Output stays temporary and never replaces
# the product companion.jar.
mapfile -t sources < <(find src/com/interop/companion -maxdepth 1 -type f -name '*.java' -print | sort)
"$java_bin/javac" --release 8 -encoding UTF-8 -cp "$sdk/platforms/android-36/android.jar" -d "$build_dir/classes" "${sources[@]}" tests/Fixture.java
mapfile -t classes < <(find "$build_dir/classes" -name '*.class' -print | sort)
"$sdk/build-tools/37.0.0/d8" --min-api 26 --lib "$sdk/platforms/android-36/android.jar" --output "$build_dir/dex" "${classes[@]}"
"$java_bin/jar" --create --file "${1:-/tmp/interop-companion-fixture.jar}" --date=2026-10-16T00:00:00Z -C "$build_dir/dex" classes.dex
