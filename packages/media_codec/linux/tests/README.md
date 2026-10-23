`gpu_texture_test.cc` links the production GL importer and fixed FFmpeg. It
creates a surfaceless EGL context and checks real pixels for planar YUV/NV12,
BT709 default metadata, a GPU/CPU storage resize cycle, and host GL state
isolation (separate read/draw FBO, PBO, unpack offsets, rasterizer discard and
pre-existing errors).

Enable `MEDIA_CODEC_BUILD_TESTS` in a Linux plugin build to get
`media_codec_gpu_texture_test`. Run it normally for software YUV upload; pass
`--vaapi` to additionally require actual VAAPI `/dev/dri/renderD128` DMA-BUF
import and twelve successive retained hardware surfaces. This mode deliberately
fails when the driver, FFmpeg libdrm build, or EGL interoperability is missing.
Set `LIBVA_DRIVERS_PATH` only if using a development driver outside system
locations. Neither mode proves Flutter composition or physical scanout.

The CUDA importer dynamically loads the driver and registers GL plane textures;
its device-to-device path needs an NVIDIA GPU sharing the current GL device for
runtime validation. An absent/incompatible driver returns to the explicit CPU
fallback rather than disabling the plugin.

`audio_test.cc` exercises the production dynamically loaded ALSA output using
the real ALSA null PCM configured by `alsa-null.conf`. It checks accepted bytes,
queue/clock accounting and pause drop/prepare generations. CTest injects this
configuration so it does not play sound or depend on the user's default route;
it does not prove a physical speaker or route-change notification.
