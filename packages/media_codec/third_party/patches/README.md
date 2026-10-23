# Controlled FFmpeg patch

`ffmpeg.lock.json` pins upstream and patch SHA-256 values. `tool/build_ffmpeg.py` verifies them, builds a separate tree and records the combined identity; patch changes invalidate platform prefixes. Corresponding source must include the original archive, exact patches, lock, configuration and notices.

`0001-remote-decode-platform-contract.patch`, against `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`, adds component-name inspection, NDK output-Surface switching, low-latency requests and strict VideoToolbox hardware selection under LGPL-2.1-or-later.

Android extensions run only on the decoder thread. Surface switching requires a non-null `ANativeWindow`, retains the new window before releasing old references and preserves failure; unsupported combinations return negative errors so the caller can recreate. A low-latency request does not prove OEM support.
