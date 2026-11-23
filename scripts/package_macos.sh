#!/usr/bin/env bash
set -euo pipefail
bundle="$1"
image="$2"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
staged="$stage/Interconnect.app"
ditto "$bundle" "$staged"
ln -s /Applications "$stage/Applications"

if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  # 从内到外更新发布签名。Flutter 编译时生成的应用身份与权限保持不变。
  while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q 'Mach-O'; then
      codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$file"
    fi
  done < <(find "$staged/Contents" -type f -print0)
  while IFS= read -r -d '' framework; do
    codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$framework"
  done < <(find "$staged/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
  codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" \
    --entitlements app/macos/Runner/Release.entitlements "$staged"
  codesign --verify --deep --strict "$staged"
fi

hdiutil create -ov -format UDZO -volname Interconnect -srcfolder "$stage" "$image"
hdiutil verify "$image"

if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$image"
  receipt="$(xcrun notarytool submit "$image" --wait --output-format json \
    --key "$MACOS_NOTARY_KEY_PATH" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER")"
  printf '%s\n' "$receipt"
  [[ "$(printf '%s' "$receipt" | plutil -extract status raw -o - -)" = Accepted ]]
  xcrun stapler staple "$image"
  xcrun stapler validate "$image"
fi
