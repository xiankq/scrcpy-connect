The optional `MEDIA_CODEC_BUILD_TESTS=ON` CMake configuration builds
`media_codec_wasapi_test` against the production Windows sink and current Rust
core. Run it on Windows with an available default render endpoint and
`flutter_windows.dll` on PATH. The test submits silence, checks actual device
clock progress, pauses/resets/resumes, and closes twice on the owning thread.
It does not switch a user's default endpoint or prove audible speaker output.

For the Flutter texture consumer, use the independent pinned AV1 replay in
`app/integration_test/media_texture_replay_test.dart`; its build and fixture
instructions are in `native/tests/README.md`.
