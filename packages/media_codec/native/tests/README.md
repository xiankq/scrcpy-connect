The lifecycle test checks generation rejection, bounded input, actual PCM write
accounting, pause and synchronous detach through the public C ABI.

`video_decode_test.cpp` accepts the AV1 fixture from
<https://fate-suite.ffmpeg.org/av1/decode_model.ivf> (SHA-256
`956947f45c96ea1f944fc2aac646d9088a307e436b2afc0477b9ae627babc7cd`).
Keep the downloaded fixture in a system temporary directory. The harness removes
the IVF test envelope itself and submits each original packet through SinkV1;
the production decoder links no AVFormat/demuxer. It explicitly disables hardware
selection, checks all 24 displayed frames and `libdav1d` status, reads a bounded
nonblank RGBA snapshot, and verifies detach on disposal.

Link either harness against `media_codec_native` and its pinned FFmpeg/dav1d
static dependencies. On MSVC use `/MD`, matching Flutter and the dependency
profile. Both Linux x64 and Windows x64 have run the AV1 harness against the Rust
core; GPU presentation is a separate Flutter integration acceptance step.

An optional second argument, such as `d3d11va` or `vaapi`, requires actual AV1
hardware frames rather than allowing a software fallback. Run this only where
the selected device supports AV1; its successful RGBA readback still does not
verify a Flutter texture's presentation.

The Windows texture regression uses `texture_replay_source.cpp` as a test-only
SinkV1 producer and `app/integration_test/media_texture_replay_test.dart` as the
real Flutter consumer. The fixture is the same pinned FATE AV1 input above. The
test decodes all 24 packets, reads pixels from a RepaintBoundary containing only
the external texture, and repeats creation/disposal three times. A solid black
texture cannot pass through text, a debug banner, or another widget's colors.
It reproduced ANGLE's rejection of an independent device's raw D3D texture
pointer, and passes when the plugin imports the DXGI shared handle instead.

From a Visual Studio developer PowerShell at the repository root, download the
fixture into the system temporary directory and verify its SHA-256 above, then:

```powershell
$env:MEDIA_CODEC_REPLAY_FIXTURE = "$env:TEMP/decode_model.ivf"
$library = "$env:TEMP/media_texture_replay.dll"
cl /nologo /W4 /WX /MD /std:c++17 /EHsc /LD `
  packages/media_codec/native/tests/texture_replay_source.cpp `
  /Fe:$library /Fo:"$env:TEMP/media_texture_replay.obj"
Set-Location app
flutter drive --profile -d windows `
  --target=integration_test/media_texture_replay_test.dart `
  --driver=../tool/driver/media_texture_replay.dart `
  --dart-define=MEDIA_CODEC_REPLAY_LIBRARY=$library
```

No ADB server or Android target is used. Keep the replay DLL/import library,
object, fixture and driver output in temporary storage; none ships with the
application. The driver writes successful or failed response data to
`<system temporary directory>/connect-e2e/media-texture-replay/result.json`.
This tests software AV1 fallback plus GPU upload/presentation on a
machine without AV1 hardware; the device-backed H264 performance test separately
checks hardware decoding and actual fixture-counter freshness.
