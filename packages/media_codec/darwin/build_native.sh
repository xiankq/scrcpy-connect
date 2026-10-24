#!/bin/sh
# CocoaPods 在静态库和 framework 的编译前均执行此脚本。
set -eu
mc_platform="$1"
mc_package_root="$(cd "$PODS_TARGET_SRCROOT/.." && pwd)"
mc_sdk_root="$(xcrun --sdk "$PLATFORM_NAME" --show-sdk-path)"
mc_clang="$(xcrun --sdk "$PLATFORM_NAME" --find clang)"
mc_cargo="${CARGO_HOME:-$HOME/.cargo}/bin/cargo"
if [ ! -x "$mc_cargo" ]; then mc_cargo="$(command -v cargo)"; fi
mc_cargo_target_dir="$PODS_CONFIGURATION_BUILD_DIR/media_codec_rust/$PLATFORM_NAME"
for mc_apple_arch in $ARCHS; do
  case "$mc_apple_arch" in
    arm64) mc_ffmpeg_arch=arm64; mc_rust_arch=aarch64 ;;
    x86_64) mc_ffmpeg_arch=x64; mc_rust_arch=x86_64 ;;
    *) echo "Unsupported media_codec Apple architecture: $mc_apple_arch" >&2; exit 1 ;;
  esac
  if [ "$mc_platform" = macos ]; then
    mc_rust_target="$mc_rust_arch-apple-darwin"
  elif [ "$PLATFORM_NAME" = iphonesimulator ] && [ "$mc_rust_arch" = aarch64 ]; then
    mc_rust_target=aarch64-apple-ios-sim
  else
    mc_rust_target="$mc_rust_arch-apple-ios"
  fi
  mc_ffmpeg_prefix="${MEDIA_CODEC_FFMPEG_ROOT:-$PODS_CONFIGURATION_BUILD_DIR/media_codec_ffmpeg/$PLATFORM_NAME/$mc_apple_arch}"
  if [ -z "${MEDIA_CODEC_FFMPEG_ROOT:-}" ]; then
    python3 "$mc_package_root/tool/build_ffmpeg.py" --platform "$mc_platform" --arch "$mc_ffmpeg_arch" \
      --sdk "$PLATFORM_NAME" --prefix "$mc_ffmpeg_prefix"
  fi
  (
    cd "$mc_package_root/../../rust/media_codec"
    export MEDIA_CODEC_FFMPEG_ROOT="$mc_ffmpeg_prefix"
    export MEDIA_CODEC_SYSROOT="$mc_sdk_root"
    export LIBCLANG_PATH="${LIBCLANG_PATH:-$(dirname "$mc_clang")/../lib}"
    export SDKROOT="$mc_sdk_root"
    export IPHONEOS_DEPLOYMENT_TARGET=13.0
    export MACOSX_DEPLOYMENT_TARGET=10.15
    export CARGO_INCREMENTAL=0
    "$mc_cargo" build --release --lib --locked --target "$mc_rust_target" --target-dir "$mc_cargo_target_dir"
  )
  # Rust staticlib 已包含三个裁剪后的 FFmpeg 库。
  ln -sf "$mc_cargo_target_dir/$mc_rust_target/release/libmedia_codec_native.a" \
    "$mc_ffmpeg_prefix/lib/libmedia_codec_native.a"
done
