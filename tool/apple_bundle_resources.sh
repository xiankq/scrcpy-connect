#!/bin/sh
# Run after Flutter embedding and before Xcode signs the enclosing application.
set -eu
ab_workspace="$(cd "$PROJECT_DIR/../.." && pwd)"
ab_resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$ab_resources"
if [ "$PLATFORM_NAME" = macosx ]; then
  ab_dart="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
  "$ab_dart" "$ab_workspace/packages/flutter_adb/tool/prepare_adb.dart" \
    --platform macos --output "$ab_workspace/.dart_tool/flutter_adb/macos"
  ab_adb="$ab_resources/adb"
  mkdir -p "$ab_adb"
  # prepare_adb validates every selected file against the checked-in lock.
  cp "$ab_workspace/.dart_tool/flutter_adb/macos/"* "$ab_adb/"
  chmod 755 "$ab_adb/adb"
  # Nested executable signing must happen before the outer app is signed.
  if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    ab_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    [ -n "$ab_identity" ] || ab_identity=-
    /usr/bin/codesign --force --sign "$ab_identity" --timestamp=none \
      --options runtime "$ab_adb/adb"
  fi
fi
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
