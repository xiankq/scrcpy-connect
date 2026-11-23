# Source from the macOS release runner. The keychain and files live only for this step.
: "${MACOS_CERTIFICATE_BASE64:?Missing Developer ID certificate}"
: "${MACOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${MACOS_SIGNING_IDENTITY:?Missing Developer ID signing identity}"
: "${MACOS_NOTARY_KEY_BASE64:?Missing App Store Connect API key}"
: "${MACOS_NOTARY_KEY_ID:?Missing API key ID}"
: "${MACOS_NOTARY_ISSUER:?Missing API issuer ID}"
umask 077
macos_signing_dir="$(mktemp -d)"
macos_keychain="$macos_signing_dir/interconnect.keychain-db"
trap 'security delete-keychain "$macos_keychain" >/dev/null 2>&1 || true; rm -rf "$macos_signing_dir"' EXIT
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$macos_signing_dir/identity.p12"
export MACOS_NOTARY_KEY_PATH="$macos_signing_dir/notary.p8"
printf '%s' "$MACOS_NOTARY_KEY_BASE64" | base64 --decode > "$MACOS_NOTARY_KEY_PATH"
unset MACOS_CERTIFICATE_BASE64 MACOS_NOTARY_KEY_BASE64
macos_keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$macos_keychain_password" "$macos_keychain"
security set-keychain-settings -lut 5400 "$macos_keychain"
security unlock-keychain -p "$macos_keychain_password" "$macos_keychain"
security import "$macos_signing_dir/identity.p12" -k "$macos_keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$macos_keychain_password" "$macos_keychain"
security list-keychains -d user -s "$macos_keychain" "$HOME/Library/Keychains/login.keychain-db"
