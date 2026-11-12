# Controlled FFmpeg patch

`ffmpeg.lock.json` pins upstream and patch SHA-256 values. `tool/build_ffmpeg.py` verifies them, builds a separate tree and records the combined identity; patch changes invalidate platform prefixes. Corresponding source must include the original archive, exact patches, lock, configuration and notices.

`0001-remote-decode-platform-contract.patch`, against `986bab2b47540c3d45d1299a40a3b103b344323c`, adds component-name inspection, NDK output-Surface switching, low-latency requests and strict VideoToolbox hardware selection under LGPL-2.1-or-later.

Android extensions run only on the decoder thread. Surface switching requires a non-null `ANativeWindow`, retains the new window before releasing old references and preserves failure; unsupported combinations return negative errors so the caller can recreate. A low-latency request does not prove OEM support.
