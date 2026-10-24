import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/files/sharing/share_scope_recovery.dart';

class ScopeFixture implements NativeLocalFilesApi {
  final calls = <String>[];
  final closing = Completer<void>();
  Completer<void>? drain;
  bool failClose = false;
  @override
  Future<String> openScope(
    String key,
    List<Uint8List> roots,
    int timeout,
  ) async {
    calls.add('open:$key');
    return 'scope';
  }

  @override
  Future<void> closeScope(String id, int timeout) async {
    calls.add('close');
    if (!closing.isCompleted) closing.complete();
    if (failClose) {
      throw const LocalFileException(
        LocalFileErrorCode.cleanupUnconfirmed,
        '尚未排空',
      );
    }
    await drain?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('接管必须先确认 SDK 排空；平台已提交但丢回执仍重用原候选', () async {
    final directory = await Directory.systemTemp.createTemp('share-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    final api = ScopeFixture()..drain = Completer<void>();
    var lease = 'old';
    var ready = false;
    var loseReply = true;
    final candidates = <String>[];
    Future<Map<String, dynamic>> platform(
      String command,
      Map<String, dynamic> params,
    ) async {
      if (command.endsWith('environment')) {
        return {
          'cacheDirectory': directory.path,
          'ownerLeaseId': lease,
          'ownerReady': ready,
        };
      }
      api.calls.add('claim');
      candidates.add(params['ownerLeaseId'] as String);
      expect(
        params['expectedOwnerLeaseId'] == lease ||
            params['ownerLeaseId'] == lease,
        isTrue,
      );
      lease = params['ownerLeaseId'] as String;
      ready = true;
      if (loseReply) throw StateError('回执丢失');
      return {'claimed': true, 'ownerLeaseId': lease};
    }

    Future<LocalFiles> files() async => LocalFiles(api);
    final first = ShareScopeRecovery.confirm(files: files, platform: platform);
    await api.closing.future;
    expect(api.calls, [endsWith('/incoming'), 'close']);
    expect(candidates, isEmpty);
    api.drain!.complete();
    await expectLater(first, throwsStateError);
    loseReply = false;
    final owner = await ShareScopeRecovery.confirm(
      files: files,
      platform: platform,
    );
    expect(candidates, hasLength(2));
    expect(candidates[0], candidates[1]);
    expect(api.calls.where((call) => call.startsWith('open:')), hasLength(1));
    expect(owner.leaseId, lease);

    ready = false;
    await ShareScopeRecovery.confirm(files: files, platform: platform);
    expect(api.calls.where((call) => call.startsWith('open:')), hasLength(2));
    expect(candidates.last, isNot(candidates.first));
  });
}
