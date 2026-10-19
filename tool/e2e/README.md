# Host E2E tools

All repository-owned host tools in this directory run with the repository's
Dart SDK and locked pub dependencies. Run `flutter pub get` from the repository
root once after changing dependencies. These tools also support an unrelated
working directory when invoked using an absolute script path.

Build an independent Android fixture using the installed Android SDK:

```sh
dart tool/e2e/build_fixture.dart video
```

The first argument selects `video`, `audio-focus`, `input`, `share`,
`notification`, or `content-delivery`. The six fixture directories also retain a
`build.dart` entry point with the same `--sdk` and `--output` options. They share
one implementation. Generated APKs and disposable signing keys default to the
system temporary directory; notification and content-delivery output paths must
remain below that directory. A local APK build neither installs nor validates a fixture
on a device.

Offline analysis entries keep their existing flags and JSON evidence fields:

| Entry point | Purpose |
| --- | --- |
| `analyze_decoder_trace.dart` | Correlate an ordinary Driver benchmark with target codec slices and player markers |
| `video_fixture/analyze_codec_trace.dart` | Match raw-drain PTS to target CCodec callbacks |
| `video_fixture/analyze_capture_slots.dart` | Reconstruct observed BufferQueue slot lifetimes and time-weighted occupancy |
| `video_fixture/analyze_first_counter.dart` | Match every decoded raw-drain frame and select the earliest new counter |
| `video_fixture/analyze_player_archive.dart` | Match earliest new counters in one complete player archive to raw and snapshot observations |

Invoke each using `dart tool/e2e/<entry> --help`. Perfetto analysis
still requires the official host `trace_processor query` CLI. Counter decoding
still requires an explicitly selected host FFmpeg, and requires microsecond
showinfo PTS and exact 64×64 RGBA frame lengths. The analyzers retain their
original clock assumptions, incomplete-evidence failures, and overwrite policy.

`video_fixture/capture_first_counter.dart` keeps the lab raw H264 drain workflow:
it requires explicit `--adb`, `--target`, `--jar`, `--fixture`, and new `--out`
paths. It installs only a fixture absent before the run and records cleanup
outcomes independently. Use it only with a dedicated authorized target. It does
not qualify product or Flutter latency.

Run all analyzer regressions without accessing a device:

```sh
flutter test --no-pub tool/e2e/tests
```

The SQL-literal regression exercises the host SQLite library through Dart FFI,
including a process name containing a SQL injection payload.
