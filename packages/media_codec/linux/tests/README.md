# Linux native tests

Enable `MEDIA_CODEC_BUILD_TESTS` in a Linux plugin build.

- `media_codec_gpu_texture_test` checks production GL YUV/NV12 pixels, resize and caller GL-state isolation in surfaceless EGL. `--vaapi` additionally requires `/dev/dri/renderD128` DMA-BUF import and retained hardware surfaces; missing driver/libdrm/EGL support fails explicitly. `LIBVA_DRIVERS_PATH` is only needed for a non-system development driver.
- `audio_test.cc` uses production ALSA with `alsa-null.conf`, injected by CTest, to check bytes, queue/clock accounting and pause generations without sound or the user's default route.

CUDA/GL interop additionally needs an NVIDIA GPU sharing the GL device; incompatible hardware uses explicit CPU fallback. These tests do not prove Flutter composition or physical output; see [native replay](../../native/tests/README.md).
