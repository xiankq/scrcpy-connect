import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/companion_recovery.dart';

import 'coordinator_fixture.dart';

void main() {
  test('starting事件消费者首败也回收登记，同一连接后续能正常部署', () async {
    final fixture = CoordinatorFixture();
    fixture.rejectStartingEvent = true;
    await expectLater(
      fixture.companion.command('apps.list', {
        'filter': 'running',
        'deviceId': 'phone',
      }),
      throwsA(isA<StateError>()),
    );
    expect(fixture.api.created, isEmpty);
    expect(fixture.companion.hasActive('phone'), isFalse);
    fixture.api.onRequest = (request) => fixture.reply(request, {'apps': []});
    final result = await fixture.companion.command('apps.list', {
      'filter': 'running',
      'deviceId': 'phone',
    });
    expect(result['apps'], isEmpty);
    expect(fixture.api.created.where((id) => id.startsWith('push')).length, 1);
    await fixture.companion.close();
    expect(fixture.api.live, isEmpty);
  });

  test('allowStart:false及非法图标请求不触发上传或部署', () async {
    final fixture = CoordinatorFixture();
    await expectLater(
      fixture.companion.command('apps.list', {
        'deviceId': 'phone',
        'filter': 'running',
        'allowStart': false,
      }),
      throwsA(companionCode('observation_required')),
    );
    expect(
      () => fixture.companion.command('apps.icon', {
        'deviceId': 'phone',
        'packageName': '../evil',
      }),
      throwsA(companionCode('invalid_argument')),
    );
    expect(
      () => fixture.companion.command('apps.list', {
        'deviceId': 'phone',
        'filter': 'running',
        'allowStart': 'false',
      }),
      throwsA(companionCode('invalid_argument')),
    );
    expect(fixture.api.created, isEmpty);
    await fixture.companion.close();
  });

  test('同连接并发应用读取只部署一次，返回真实running与icon回执', () async {
    final fixture = CoordinatorFixture();
    fixture.api.onRequest = (request) => fixture.reply(
      request,
      request['command'] == 'apps.list'
          ? {
              'apps': [
                {'packageName': 'com.test', 'taskId': 7},
              ],
            }
          : {'icon': '真实图标'},
    );
    final results = await Future.wait([
      fixture.companion.command('apps.list', {
        'deviceId': 'phone',
        'filter': 'running',
      }),
      fixture.companion.command('apps.icon', {
        'deviceId': 'phone',
        'packageName': 'com.test',
      }),
    ]);
    expect((results[0]['apps']! as List).single, {
      'packageName': 'com.test',
      'taskId': 7,
    });
    expect(results[1]['icon'], '真实图标');
    expect(fixture.api.created.where((id) => id.startsWith('push')).length, 1);
    expect(fixture.api.created.where((id) => id.startsWith('rpc')).length, 1);
    await fixture.companion.close();
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('installed筛选不能误交付running列表，无效筛选也不启动服务', () async {
    final fixture = CoordinatorFixture();
    expect(
      () => fixture.companion.command('apps.list', {'deviceId': 'phone'}),
      throwsA(companionCode('unsupported')),
    );
    expect(
      () => fixture.companion.command('apps.list', {
        'deviceId': 'phone',
        'filter': 'installed',
      }),
      throwsA(companionCode('unsupported')),
    );
    expect(
      () => fixture.companion.command('apps.list', {
        'deviceId': 'phone',
        'filter': 'unknown',
      }),
      throwsA(companionCode('invalid_argument')),
    );
    expect(fixture.api.created, isEmpty);
    await fixture.companion.close();
  });

  test('精确旧连接停止拒绝迟到应用回执，不影响新连接部署', () async {
    final fixture = CoordinatorFixture();
    final issued = fixture.api.requests.stream.first;
    final pending = expectLater(
      fixture.companion.command('apps.list', {
        'filter': 'running',
        'deviceId': 'phone',
      }),
      throwsA(companionCode('cancelled')),
    );
    await issued;
    final old = fixture.current!;
    fixture.replaceConnection();
    await fixture.companion.stopForConnection('phone', old);
    await pending;
    fixture.api.onRequest = (request) => fixture.reply(request, {'apps': []});
    expect(
      (await fixture.companion.command('apps.list', {
        'filter': 'running',
        'deviceId': 'phone',
      }))['apps'],
      isEmpty,
    );
    await fixture.companion.stopForConnection('phone', old);
    expect(fixture.companion.hasActive('phone'), isTrue);
    await fixture.companion.close();
  });

  test('断线先排空本机并持久移交，重建后仅核验同设备原部署再偿清', () async {
    final root = await Directory.systemTemp.createTemp('companion-recovery-');
    addTearDown(() => root.delete(recursive: true));
    final fixture = CoordinatorFixture(recovery: CompanionRecovery(root));
    fixture.api.onRequest = (request) => fixture.reply(request, {'apps': []});
    await fixture.companion.command('apps.list', {
      'filter': 'running',
      'deviceId': 'phone',
    });
    fixture.api.transportClosed = true;
    await fixture.companion.stopForConnection('phone', fixture.current!);
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.commands, isEmpty);
    final restored = CompanionRecovery(root);
    final candidate = fixture.replaceConnection();
    await expectLater(
      restored.recover('phone', 'other', candidate, AdbCancellation()),
      throwsA(companionCode('cleanup_unconfirmed')),
    );
    fixture.api.wrongIdentity = true;
    await expectLater(
      restored.recover('phone', 'serial', candidate, AdbCancellation()),
      throwsA(companionCode('remote_process_error')),
    );
    expect(fixture.api.commands.single, contains('expected=9001'));
    fixture.api.wrongIdentity = false;
    await fixture.companion.prepareConnection(
      'phone',
      candidate,
      'serial',
      AdbCancellation(),
    );
    expect(fixture.api.commands.last, contains('rm -f --'));
    final count = fixture.api.commands.length;
    await restored.recover('phone', 'serial', candidate, AdbCancellation());
    expect(fixture.api.commands.length, count);
    await fixture.companion.close();
  });

  test('剪贴板权限错误如实呈现，失效连接事件不发布给后继设备', () async {
    final fixture = CoordinatorFixture();
    fixture.api.onRequest = (request) => fixture.api.message({
      'requestId': request['requestId'],
      'error': {'code': 'clipboard_unavailable', 'message': '后台读取受限'},
    });
    await expectLater(
      fixture.companion.command('clipboard.get', {'deviceId': 'phone'}),
      throwsA(companionCode('clipboard_unavailable')),
    );
    expect(
      (fixture.companion.capabilityState('phone')['clipboard']! as Map)['live'],
      isFalse,
    );
    fixture.replaceConnection();
    fixture.api.message({
      'event': 'clipboard.changed',
      'data': {'text': '旧秘密'},
    });
    await Future<void>.value();
    expect(
      fixture.emitted.where((event) => event.type == 'clipboard.changed'),
      isEmpty,
    );
    await fixture.companion.close();
  });

  test('部署创建迟到时关闭等待真实句柄并拒绝交付，避免孤儿部署', () async {
    final fixture = CoordinatorFixture();
    fixture.api.execGate = Completer<void>();
    final pending = expectLater(
      fixture.companion.command('apps.list', {
        'filter': 'running',
        'deviceId': 'phone',
      }),
      throwsA(anything),
    );
    await fixture.api.execCreated.future;
    final closing = expectLater(
      fixture.companion.close(),
      throwsA(companionCode('cleanup_unconfirmed')),
    );
    fixture.api.execGate!.complete();
    await pending;
    await closing;
    expect(fixture.api.live, isEmpty);
    expect(fixture.companion.hasActive('phone'), isFalse);
    expect(fixture.api.disconnected, isEmpty);
  });
}
