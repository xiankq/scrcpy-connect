import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';

void main() {
  test('按需附着文件查询仍使用唯一事件序列，退休后拒绝新增订阅', () async {
    final events = RuntimeEvents(
      acceptState: (_) => true,
      onState: (_) {},
      beforePublish: (_) {},
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    await events.attach(files: []);
    final source = StreamController<RuntimeEvent>.broadcast(sync: true);
    events.attachFileEvents(source.stream);
    final received = events.stream.first;
    source.add({'type': 'files.changed', 'path': '/sdcard'});
    expect(await received, {
      'type': 'files.changed',
      'path': '/sdcard',
      'data': {'path': '/sdcard'},
      'sequence': 1,
    });
    expect(events.cursor, (sequence: 1, revision: 1));
    await events.detach();
    expect(source.hasListener, isFalse);
    expect(() => events.attachFileEvents(source.stream), throwsStateError);
    await source.close();
    await events.close();
  });
}
