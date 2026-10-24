import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/companion/observation_coordinator.dart';
import 'package:scrcpy_connect/connection/records/device_record_store.dart';

import 'coordinator_fixture.dart';

void main() {
  late _ObservationFixture fixture;
  setUp(() async {
    fixture = await _ObservationFixture.open();
  });
  tearDown(() async {
    await fixture.close();
  });

  test('缓存connected与默认wanted不证明观察存活，明确stop才投影stopped', () async {
    await fixture.records.update(
      fixture.id,
      (record) => record.copyWith(status: 'connected'),
    );
    fixture.base.current = null;
    expect(fixture.records.current.find(fixture.id)!.observationWanted, isTrue);
    final status = await fixture.command('observation.status');
    expect(status['phase'], 'waiting_connection');
    expect(status['wanted'], isTrue);
    expect(
      (await fixture.observation.command(
        'observation.list',
        {},
      ))['observations'],
      hasLength(1),
    );
    final notifications = await fixture.command('notifications.list', {
      'allowStart': false,
    });
    expect(notifications, containsPair('status', 'unknown'));
    expect(notifications, containsPair('live', false));
    await expectLater(
      fixture.command('notifications.open', {'key': 'old'}),
      throwsA(companionCode('observation_required')),
    );
    expect(fixture.base.api.created, isEmpty);
    final stopped = await fixture.command('observation.stop');
    expect(stopped['phase'], 'stopped');
    expect((await fixture.command('notifications.list'))['status'], 'stopped');
    expect(
      fixture.records.current.find(fixture.id)!.observationWanted,
      isFalse,
    );
    expect(fixture.base.api.created, isEmpty);
  });

  test('显式allowStart:false也不部署，后续状态读取不会补启动', () async {
    await expectLater(
      fixture.command('observation.start', {'allowStart': false}),
      throwsA(companionCode('observation_required')),
    );
    expect((await fixture.command('observation.status'))['phase'], 'failed');
    await fixture.command('notifications.list');
    expect(fixture.base.api.created, isEmpty);
  });

  test('意图持久化失败不部署，也不能由后续连接钩子绕过失败', () async {
    await fixture.records.setObservationWanted(fixture.id, false);
    final before = await fixture.records.file.readAsString();
    final commits = fixture.writes.attempts;
    fixture.writes.fail = true;
    await expectLater(
      fixture.command('observation.start'),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          '持久化受控失败',
        ),
      ),
    );
    expect(fixture.writes.attempts, commits + 1);
    expect(await fixture.records.file.readAsString(), before);
    expect(
      (await DeviceRecordStore.open(directory: fixture.directory)).current
          .find(fixture.id)!
          .observationWanted,
      isFalse,
    );
    expect(fixture.observation.status(fixture.id)['phase'], 'failed');
    await fixture.observation.connectionChanged(fixture.id);
    expect(fixture.base.api.created, isEmpty);
    fixture.writes.fail = false;
    expect((await fixture.command('observation.start'))['phase'], 'limited');
    expect(
      (await DeviceRecordStore.open(directory: fixture.directory)).current
          .find(fixture.id)!
          .observationWanted,
      isTrue,
    );
  });

  test('显式start先持久化意图，再按实际权限返回limited与真实版本', () async {
    await fixture.records.setObservationWanted(fixture.id, false);
    fixture.notificationsLive = false;
    final result = await fixture.command('observation.start');
    expect(result['phase'], 'limited');
    expect((result['notifications']! as Map)['live'], isFalse);
    final reopened = await DeviceRecordStore.open(directory: fixture.directory);
    expect(reopened.current.find(fixture.id)!.observationWanted, isTrue);
    expect(fixture.base.companion.capabilityState(fixture.id)['protocol'], 1);
    expect(fixture.base.companion.capabilityState(fixture.id)['apiLevel'], 35);
    final listed = await fixture.command('notifications.list');
    expect(listed['reason'], '真实权限受限');
    expect(listed['status'], 'limited');
    await expectLater(
      fixture.command('notifications.dismiss', {'key': 'x'}),
      throwsA(companionCode('observation_required')),
    );
    expect(fixture.base.api.receivedCommands, ['observation.set']);
  });

  test('停止持久化false且保留clipboard同一部署，旧代通知事件不复活', () async {
    await fixture.command('observation.start');
    final oldEpoch = fixture.epoch;
    final stopped = await fixture.command('observation.stop');
    expect(stopped['phase'], 'stopped');
    expect(
      fixture.records.current.find(fixture.id)!.observationWanted,
      isFalse,
    );
    fixture.changed(
      epoch: oldEpoch,
      items: [
        {'key': 'stale'},
      ],
    );
    final clipboard = await fixture.base.companion.command('clipboard.get', {
      'deviceId': fixture.id,
    });
    expect(clipboard['text'], '文字');
    expect(fixture.base.companion.hasActive(fixture.id), isTrue);
    expect(
      fixture.base.api.created.where((id) => id.startsWith('push')).length,
      1,
    );
    expect(
      fixture.base.emitted.where(
        (event) => event.type == 'notifications.changed',
      ),
      isEmpty,
    );
    expect(
      (fixture.observation.status(fixture.id)['notifications']! as Map)['live'],
      isFalse,
    );
  });

  test('事件先于较旧list回执到达，旧快照不得覆盖较新实时内容', () async {
    await fixture.command('observation.start');
    final issued = Completer<Map<String, Object?>>();
    fixture.base.api.onRequest = (request) {
      if (request['command'] == 'notifications.list') {
        issued.complete(request);
      } else {
        fixture.autoReply(request);
      }
    };
    final pending = fixture.command('notifications.list');
    final request = await issued.future;
    final emitted = Completer<void>();
    final sub = fixture.base.companion.updates.listen((update) {
      if (update.type == 'notifications.changed' && !emitted.isCompleted) {
        emitted.complete();
      }
    });
    fixture.changed(
      items: [
        {'key': 'new'},
      ],
    );
    await emitted.future;
    fixture.base.reply(
      request,
      fixture.section(
        'notifications',
        items: [
          {'key': 'old'},
        ],
      ),
    );
    expect((await pending)['notifications'], [
      {'key': 'new'},
    ]);
    expect(
      (fixture.observation.status(fixture.id)['notifications']!
          as Map)['notifications'],
      [
        {'key': 'new'},
      ],
    );
    await sub.cancel();
  });

  test('停观察立即撤销在途列表回执，既有通知动作不能跨代交付', () async {
    await fixture.command('observation.start');
    final issued = Completer<Map<String, Object?>>();
    fixture.base.api.onRequest = (request) {
      if (request['command'] == 'notifications.list') {
        issued.complete(request);
      } else {
        fixture.autoReply(request);
      }
    };
    final pending = expectLater(
      fixture.command('notifications.list'),
      throwsA(companionCode('cancelled')),
    );
    final old = await issued.future;
    await fixture.command('observation.stop');
    await pending;
    fixture.base.reply(
      old,
      fixture.section(
        'notifications',
        items: [
          {'key': 'late'},
        ],
      ),
    );
    expect((await fixture.command('notifications.list'))['status'], 'stopped');
  });

  test('恢复前台只核验既有helper，不重新部署已经结束的观察', () async {
    await fixture.command('observation.start');
    fixture.observation.pause();
    await fixture.base.companion.stopForConnection(
      fixture.id,
      fixture.base.current!,
    );
    await fixture.observation.resume();
    expect(
      fixture.base.api.created.where((id) => id.startsWith('push')).length,
      1,
    );
    expect((await fixture.command('notifications.list'))['live'], isFalse);
    expect(fixture.records.current.find(fixture.id)!.observationWanted, isTrue);
  });

  test('明确发布新连接才恢复持久观察，旧连接事件不污染新epoch', () async {
    await fixture.command('observation.start');
    final old = fixture.base.current!;
    fixture.base.replaceConnection();
    await fixture.observation.connectionChanged(fixture.id);
    expect(
      fixture.base.api.created.where((id) => id.startsWith('push')).length,
      2,
    );
    expect(fixture.observation.status(fixture.id)['phase'], 'limited');
    await fixture.observation.stopForConnection(fixture.id, old);
    expect(fixture.base.companion.hasActive(fixture.id), isTrue);
    final before = fixture.base.emitted
        .where((event) => event.type == 'notifications.changed')
        .length;
    fixture.changed(
      epoch: 1,
      items: [
        {'key': 'old epoch'},
      ],
    );
    await fixture.command('notifications.list');
    expect(
      fixture.base.emitted
          .where((event) => event.type == 'notifications.changed')
          .length,
      before,
    );
  });

  test('通话入口只打开系统界面，指定callId和未交付逐通话动作如实拒绝', () async {
    await fixture.command('observation.start');
    await expectLater(
      fixture.command('calls.open', {'callId': 'stale'}),
      throwsA(companionCode('call_targeting_unavailable')),
    );
    fixture.base.api.onRequest = (request) {
      if (request['command'] == 'calls.action') {
        fixture.base.api.message({
          'requestId': request['requestId'],
          'error': {
            'code': 'call_targeting_unavailable',
            'message': '未交付逐通话控制',
          },
        });
      } else {
        fixture.autoReply(request);
      }
    };
    await expectLater(
      fixture.command('calls.action', {'callId': 'x', 'action': 'answer'}),
      throwsA(companionCode('call_targeting_unavailable')),
    );
    final result = await fixture.command('calls.open');
    expect(result['requested'], isTrue);
    expect(result.containsKey('visible'), isFalse);
    final calls = await fixture.command('calls.list');
    expect(
      (calls['calls']! as List).single,
      containsPair('deviceName', '测试手机'),
    );
  });

  test('监听清理未确认不伪报observing，保留失败状态供明确重试', () async {
    var first = true;
    fixture.base.api.onRequest = (request) {
      if (request['command'] == 'observation.set' && first) {
        first = false;
        fixture.epoch = request['epoch']! as int;
        fixture.base.reply(request, {
          'observationEpoch': fixture.epoch,
          'observationEnabled': true,
          'cleanupConfirmed': false,
          'notifications': fixture.section('notifications'),
          'calls': fixture.section('calls'),
        });
      } else {
        fixture.autoReply(request);
      }
    };
    await expectLater(
      fixture.command('observation.start'),
      throwsA(companionCode('observation_cleanup_unknown')),
    );
    expect(fixture.observation.status(fixture.id)['phase'], 'failed');
    expect(
      (fixture.observation.status(fixture.id)['notifications']! as Map)['live'],
      isFalse,
    );
    final retried = await fixture.command('observation.start');
    expect(retried['phase'], 'limited');
  });
}

class _ObservationFixture {
  _ObservationFixture(this.directory, this.records, this.id, this.writes) {
    base.api.onRequest = autoReply;
    observation = ObservationCoordinator(
      companion: base.companion,
      records: records,
      emit: base.emit,
    );
  }
  static Future<_ObservationFixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'companion-observation-',
    );
    final writes = _Writes();
    final records = await DeviceRecordStore.open(
      directory: directory,
      commitFile: (temporary, destination) async {
        writes.attempts++;
        if (writes.fail) throw const FileSystemException('持久化受控失败');
        await temporary.rename(destination.path);
      },
    );
    final record = await records.add(
      name: '测试手机',
      address: '192.0.2.1',
      port: 5555,
      transport: DeviceTransport.tcp,
    );
    return _ObservationFixture(directory, records, record.id, writes);
  }

  final Directory directory;
  final DeviceRecordStore records;
  final String id;
  final _Writes writes;
  final base = CoordinatorFixture();
  late final ObservationCoordinator observation;
  int epoch = 0;
  bool enabled = false, notificationsLive = true;
  Map<String, Object?> section(
    String name, {
    List<Map<String, Object?>>? items,
  }) => {
    name:
        items ??
        (name == 'calls' && enabled
            ? [
                {'id': 'call'},
              ]
            : []),
    'status': !enabled
        ? 'stopped'
        : name == 'calls' || !notificationsLive
        ? 'limited'
        : 'available',
    'live': enabled && (name == 'calls' || notificationsLive),
    if (name == 'notifications' && !notificationsLive) 'reason': '真实权限受限',
    'observationEpoch': epoch,
    'observationEnabled': enabled,
  };
  void autoReply(Map<String, Object?> request) {
    final command = request['command'];
    if (command == 'observation.set') {
      epoch = request['epoch']! as int;
      enabled = request['enabled']! as bool;
      base.reply(request, {
        'observationEpoch': epoch,
        'observationEnabled': enabled,
        'cleanupConfirmed': true,
        'notifications': section('notifications'),
        'calls': section('calls'),
      });
    } else if (command == 'notifications.list') {
      base.reply(request, section('notifications'));
    } else if (command == 'calls.list') {
      base.reply(request, section('calls'));
    } else if (command == 'clipboard.get') {
      base.reply(request, {'text': '文字'});
    } else {
      base.reply(request, {'requested': true});
    }
  }

  void changed({int? epoch, List<Map<String, Object?>>? items}) =>
      base.api.message({
        'event': 'notifications.changed',
        'data': {
          ...section('notifications', items: items),
          'observationEpoch': epoch ?? this.epoch,
        },
      });
  Future<Map<String, Object?>> command(
    String name, [
    Map<String, Object?> params = const {},
  ]) => observation.command(name, {'deviceId': id, ...params});
  Future<void> close() async {
    await observation.close();
    await base.companion.close();
    await directory.delete(recursive: true);
  }
}

class _Writes {
  bool fail = false;
  int attempts = 0;
}
