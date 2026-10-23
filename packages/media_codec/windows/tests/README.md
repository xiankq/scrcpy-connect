# Windows native tests

`MEDIA_CODEC_BUILD_TESTS=ON` builds `media_codec_wasapi_test` against the production sink and Rust core. Run with an available default render endpoint and `flutter_windows.dll` on PATH. It submits silence, checks device clock progress, pause/reset/resume and idempotent close on its owning thread; it never switches the default endpoint or proves audible output.

For real Flutter texture pixels, use the [AV1 replay instructions](../../native/tests/README.md).
