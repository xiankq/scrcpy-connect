# Controlled FFmpeg changes

`ffmpeg.lock.json` fixes the upstream source archive and each patch SHA-256.
`tool/build_ffmpeg.py` verifies them, keeps the upstream source intact, and
creates a separate tree named from the upstream/patch identity. The build
receipt includes that identity; changing a patch invalidates every platform
prefix. The installed license directory includes the source lock, exact patch,
FFmpeg configuration and original license notices. Keep the original archive
and these patches together when providing corresponding source.

`0001-remote-decode-platform-contract.patch` is against FFmpeg
`2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`. It adds decoder-owned component-name
inspection, an optional NDK output-Surface switch with failure preservation,
the Android low-latency format request, and a strict VideoToolbox hardware
requirement. It changes FFmpeg under its existing LGPL-2.1-or-later terms.

The public Android extensions run on the decoder thread, never concurrently
with FFmpeg send/receive/close. The output-window operation accepts a non-null
`ANativeWindow`; unavailable symbols and incompatible codec/Surface combinations
return a negative error, allowing the caller to recreate the decoder. Success
retains the new window before dropping the previous references. A low-latency
request does not prove an OEM actually enabled a low-latency implementation.
