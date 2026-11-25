#!/bin/sh
# 在 Flutter 嵌入完成后、Xcode 为外层应用签名前运行。
set -eu
ab_resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$ab_resources"
ab_notices="$ab_resources/licenses/media_codec"
mkdir -p "$ab_notices"
for ab_arch in $ARCHS; do
  ab_prefix="${MEDIA_CODEC_FFMPEG_ROOT:-${PODS_CONFIGURATION_BUILD_DIR:-$CONFIGURATION_BUILD_DIR}/media_codec_ffmpeg/$PLATFORM_NAME/$ab_arch}"
  if [ ! -f "$ab_prefix/media-codec-build.json" ]; then
    echo "Missing pinned media_codec provenance: $ab_prefix" >&2
    exit 1
  fi
  ab_destination="$ab_notices/$PLATFORM_NAME-$ab_arch"
  mkdir -p "$ab_destination"
  cp -R "$ab_prefix/share/media_codec/." "$ab_destination/"
  cp "$ab_prefix/media-codec-build.json" "$ab_destination/"
done

if [ "$PLATFORM_NAME" = macosx ]; then
  ab_adb="$("$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
    "$PROJECT_DIR/../../packages/adb/tool/prepare_adb.dart" --platform macos)"
  ab_helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
  ab_adb_notices="$ab_resources/platform-tools"
  mkdir -p "$ab_helpers" "$ab_adb_notices"
  install -m 755 "$ab_adb/adb" "$ab_helpers/adb"
  cp "$ab_adb/NOTICE.txt" "$ab_adb/source.properties" \
    "$ab_adb/platform-tools.lock.json" "$ab_adb_notices/"
fi
