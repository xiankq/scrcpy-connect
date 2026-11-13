import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';
import 'package:scrcpy_connect/core/files/models/platform_share_notice.dart';

void main() {
  for (final cancelWhileOpening in [false, true]) {
    test('无效描述符${cancelWhileOpening ? '晚于取消到达' : '到达'}仍由原所有者排空和释放', () async {
      final cache = await Directory.systemTemp.createTemp('share-platform-');
      addTearDown(() => cache.delete(recursive: true));
      final native = _Scopes();
      final files = LocalFiles(native);
      addTearDown(files.close);
      var lease = 'previous';
      final opened = Completer<void>();
      final reply = Completer<Map<String, dynamic>>();
      final released = <String>[];
      var consumed = 0;
      final service = await FileShareService.open(
        files: () async => files,
        platform: (command, params) async {
          switch (command) {
            case 'sharing.platform.environment':
              return {
                'cacheDirectory': cache.path,
                'ownerLeaseId': lease,
                'ownerReady': true,
              };
            case 'sharing.platform.claim':
              lease = params['ownerLeaseId'] as String;
              return {'claimed': true, 'ownerLeaseId': lease};
            case 'sharing.platform.open':
              opened.complete();
              return reply.future;
            case 'sharing.platform.cancel':
              expect(native.active, 0);
              return {'cancelled': true};
            case 'sharing.platform.release':
              expect(native.active, 0);
              expect(params['ownerLeaseId'], lease);
              released.add(params['fdLeaseId'] as String);
              return {'released': true};
            case 'sharing.platform.consume':
              consumed++;
              return {'consumed': true};
            default:
              throw StateError('不应调用 $command');
          }
        },
      );
      addTearDown(service.close);
      final receiving = service.receive(
        PlatformShareNotice(
          shareId: '00000000-0000-4000-8000-000000000001',
          sourceCount: 1,
        ),
      );
      await opened.future;
      if (cancelWhileOpening) service.stopIntake();
      reply.complete({'fd': -1, 'fdLeaseId': 'original-descriptor'});
      expect((await receiving).status, IncomingShareStatus.error);
      expect(released, ['original-descriptor']);
      expect(consumed, 1);
      expect(native.active, 0);
      await service.close();
    });
  }
}

final class _Scopes implements NativeLocalFilesApi {
  var active = 0, serial = 0;
  @override
  Future<String> openScope(
    String key,
    List<Uint8List> roots,
    int timeout,
  ) async {
    active++;
    return 'scope-${++serial}';
  }

  @override
  Future<void> closeScope(String scopeId, int timeoutMs) async {
    active--;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应复制无效描述符：${invocation.memberName}');
}
