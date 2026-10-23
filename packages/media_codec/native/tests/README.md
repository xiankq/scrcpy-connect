# Native media tests

`lifecycle_test` covers source generations, input bounds, PCM accounting, pause and synchronous detach through the public C ABI. `video_decode_test.cpp` submits all 24 AV1 packets through SinkV1, forces libdav1d, checks frames/nonblank bounded RGBA and detach; no production demuxer is linked. Link against `media_codec_native` and its pinned static dependencies (`/MD` on MSVC).

Download the FATE [decode_model.ivf](https://fate-suite.ffmpeg.org/av1/decode_model.ivf) to a system temporary directory and verify SHA-256 `956947f45c96ea1f944fc2aac646d9088a307e436b2afc0477b9ae627babc7cd`. An optional second harness argument (`d3d11va`/`vaapi`) requires actual AV1 hardware frames; RGBA readback alone does not verify Flutter presentation.

## Windows Flutter texture replay

`texture_replay_source.cpp` supplies the same pinned fixture to the public `MediaCodecController` integration. The test checks 24 decoded frames, actual RepaintBoundary pixels and three create/dispose cycles. From a Visual Studio developer PowerShell at the root:

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

No ADB/device is used. Keep fixture, DLL/object/import library and output temporary; the driver writes `<system-temp>/connect-e2e/media-texture-replay/result.json`. This tests software AV1 plus GPU upload/composition, not hardware decoding or scanout. The public-controller migration still requires a Windows run.
