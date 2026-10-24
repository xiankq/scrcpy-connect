# Host E2E tools

Run root `flutter pub get` first. Host builders/analyzers use the locked Dart workspace; Flutter device tests run from `app/` with `--driver=../tool/driver/<entry>.dart` and `--target=integration_test/<entry>.dart` (benchmarks use `../tool/benchmark/`). See each fixture README for device isolation and required variables.

```sh
dart tool/e2e/build_fixture.dart video
flutter test --no-pub tool/e2e/tests
```

Builder choices are `video`, `audio-focus`, `input`, `share`, `notification` and `content-delivery`. Their local `build.dart` wrappers share `--sdk`/`--output`. APKs and disposable keys default to system temporary storage; notification/content-delivery outputs must remain there. Building never installs a fixture.

| Analyzer under `video_fixture/` | Purpose |
| --- | --- |
| `analyze_codec_trace.dart` | Match raw-drain PTS to target CCodec callbacks |
| `analyze_capture_slots.dart` | Reconstruct BufferQueue slot lifetimes/occupancy |
| `analyze_first_counter.dart` | Select the earliest new counter from every raw-drain frame |

Use `--help` for flags. Perfetto analysis requires official `trace_processor query`; counter decoding requires explicit host FFmpeg, microsecond showinfo PTS and exact 64×64 RGBA frames. Missing evidence fails rather than estimating.

`capture_first_counter.dart` is a separate lab H264 drain: explicit `--adb`, `--target`, `--jar`, `--fixture` and new `--out` are required. It installs only an absent fixture on a dedicated authorized target and records cleanup. These raw-drain measurements do not qualify Flutter latency; use the [current benchmark](../../docs/implementation/video-performance.md).

The standalone [Android tone source](audio_fixture/README.md) supplies explicit PCM input through `app_process`; it is separate from the APK builders and does not validate host playback.
