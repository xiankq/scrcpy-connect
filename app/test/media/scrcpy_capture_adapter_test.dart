import '../support/scrcpy_event_fixture.dart';

import 'package:scrcpy/scrcpy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/media/capture/scrcpy_capture_adapter.dart';

final class _Native implements NativeScrcpyApi {
  final inspected = <(String, int)>[];
  final controls = <(String, ScrcpyControlMessage)>[];
  var stops = 0;
  ScrcpyControlCompletion completion = ScrcpyControlCompletion.admitted;
  @override
  Future<ScrcpySessionInfo> inspect(
    String captureRef, {
    int generation = 1,
  }) async {
    inspected.add((captureRef, generation));
    return ScrcpySessionInfo(
      id: captureRef,
      deviceName: '设备',
      videoCodec: ScrcpyVideoCodec.h264,
      width: 1080,
      height: 1920,
      source: ScrcpyNativeSource(
        sourceId: 'source',
        generation: generation,
        codec: 'h264',
        width: 1080,
        height: 1920,
        attachAddress: 10,
        detachAddress: 20,
      ),
    );
  }

  @override
  Future<ScrcpyControlReceipt> sendControl(
    String id,
    ScrcpyControlMessage message,
  ) async {
    controls.add((id, message));
    return ScrcpyControlReceipt(completion);
  }

  @override
  Future<void> stopSession(String id) async => stops++;
  @override
  ScrcpyEventObserver openEvents(String id) => idleFixtureObserver();
  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) => throw StateError('应用附着不能创建第二个捕获');
  @override
  Future<ScrcpySessionInfo> startSession(String id) =>
      throw StateError('应用附着不能重新启动捕获');
}

void main() {
  test('附着已启动的精确捕获并保留 renderer 代次，不创建或停止捕获', () async {
    final native = _Native();
    final adapter = ScrcpyCaptureAdapter(native);
    final endpoint = await adapter.openSource({
      'sessionId': 'logical',
      'captureRef': 'logical:capture-2',
      'videoSourceId': 'source',
    }, 9);
    expect(native.inspected, [('logical:capture-2', 9)]);
    expect(endpoint['generation'], 9);
    expect(endpoint['relayId'], 'source');
    expect(endpoint['attachAddress'], 10);
    expect(native.stops, 0);
  });
}
