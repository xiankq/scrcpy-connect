import 'dart:isolate';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/window_isolate_port.dart';

void main() {
  test('同一引擎组的窗口借用原能力并收到类型化结果和错误', () async {
    final source = _Session();
    final owner = WindowIsolateOwner(source);
    final output = ReceivePort();
    addTearDown(owner.dispose);
    addTearDown(output.close);

    await Isolate.spawn(_useSession, (owner.port, output.sendPort));
    expect(await output.first, (_Frame(720, 1280), 'stale_session'));
    expect(source.frames, [1]);
  });
}

Future<void> _useSession((SendPort, SendPort) ports) async {
  final window = WindowIsolatePort<_Session>(ports.$1);
  final frame = await window.call((session, id) => session.frame(id), 1);
  try {
    await window.call((session, id) => session.frame(id), 2);
  } on RequestFailure catch (error) {
    ports.$2.send((frame, error.code));
  }
}

final class _Session {
  final frames = <int>[];
  FutureOr<_Frame> frame(int id) {
    if (id != 1) throw const RequestFailure('stale_session', '会话已更换。');
    frames.add(id);
    return const _Frame(720, 1280);
  }
}

extension type const _Frame._((int, int) dimensions) {
  const _Frame(int width, int height) : this._((width, height));
}
