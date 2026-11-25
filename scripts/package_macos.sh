#!/usr/bin/env bash
set -euo pipefail
bundle="$1"
image="$2"
stage="$(mktemp -d "$(dirname "$image")/.macos-package.XXXXXX")"
step=stage
started=$SECONDS
trap 'status=$?; if (( status != 0 )); then printf "ERROR [macOS installer/%s] Failed after %ss (exit %s)\n" "$step" "$((SECONDS - started))" "$status" >&2; fi; rm -rf "$stage"' EXIT
begin() {
  printf 'INFO [macOS installer/%s] Completed in %ss\n' "$step" "$((SECONDS - started))"
  step="$1"
  started=$SECONDS
  printf 'INFO [macOS installer/%s] Started\n' "$step"
}
mkdir "$stage/root"
staged="$stage/root/Interconnect.app"
disk="$stage/Interconnect.dmg"
ditto "$bundle" "$staged"
ln -s /Applications "$stage/root/Applications"

if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  begin 'sign application'
  # 从内到外更新发布签名。Flutter 编译时生成的应用身份与权限保持不变。
  find "$staged/Contents" -type f -exec file -0 -0 {} + |
  while IFS= read -r -d '' file && IFS= read -r -d '' type; do
    if [[ "$type" == *Mach-O* ]]; then
      codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$file"
    fi
  done
  while IFS= read -r -d '' framework; do
    codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$framework"
  done < <(find "$staged/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
  codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" \
    --entitlements app/macos/Runner/Release.entitlements "$staged"
  codesign --verify --deep --strict "$staged"
fi

begin 'create disk image'
hdiutil create -format UDZO -volname Interconnect -srcfolder "$stage/root" "$disk"

if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  begin notarize
  codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$disk"
  notary_args=(--key "$MACOS_NOTARY_KEY_PATH" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER")
  if ! receipt="$(xcrun notarytool submit "$disk" --wait --timeout 20m --output-format json "${notary_args[@]}")"; then
    printf '%s\n' "$receipt" >&2
    exit 1
  fi
  printf '%s\n' "$receipt"
  if [[ "$(printf '%s' "$receipt" | plutil -extract status raw -o - -)" != Accepted ]]; then
    id="$(printf '%s' "$receipt" | plutil -extract id raw -o - -)"
    xcrun notarytool log "$id" "${notary_args[@]}" >&2
    exit 1
  fi
  xcrun stapler staple "$disk"
  xcrun stapler validate "$disk"
fi

begin 'verify disk image'
hdiutil verify "$disk"
mv "$disk" "$image"
printf 'INFO [macOS installer/%s] Completed in %ss\n' "$step" "$((SECONDS - started))"
