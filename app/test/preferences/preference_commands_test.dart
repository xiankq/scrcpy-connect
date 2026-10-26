import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/stores/preference_store.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';
import 'package:scrcpy_connect/models/device_metadata.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/services/preference_commands.dart';
import 'package:flutter_test/flutter_test.dart';

TypeMatcher<ApplicationCommandException> errorCode(String code) =>
    isA<ApplicationCommandException>().having(
      (error) => error.code,
      'code',
      code,
    );
Map<String, dynamic> metadata([
  Map<String, Object?> settings = const {'appearance': 'dark'},
]) {
  final document = {
    'format': 'scrcpy-connect-metadata',
    'version': 1,
    'devices': [
      {
        'name': 'Phone',
        'address': 'phone.local',
        'port': 5555,
        'transport': 'tcp',
      },
    ],
    'settings': settings,
  };
  return {
    'metadata': document,
    'fingerprint': DeviceMetadata.parse(document).fingerprint,
    'importGlobalPreferences': true,
  };
}

void main() {
  late Directory directory;
  late PreferenceStore preferences;
  PreferenceCommands commands({
    PreferenceDeviceRequest? request,
    void Function(Map<String, dynamic>)? onChanged,
    Future<void> Function(bool)? applyBackgroundPolicy,
  }) => PreferenceCommands(
    preferences: preferences,
    request: request ?? (_, _) async => fail('纯偏好操作不得调用设备分派器'),
    onChanged: onChanged ?? (_) {},
    applyBackgroundPolicy: applyBackgroundPolicy,
  );

  PreferenceDeviceRequest importRequest(
    DeviceRecordStore records, {
    void Function()? onRequest,
  }) => (command, params) async {
    onRequest?.call();
    if (command == 'settings.import.preview') {
      return records.previewMetadata(params['metadata']);
    }
    return (await records.importMetadata(
      params['metadata'],
      expectedFingerprint: params['fingerprint'] as String?,
      importGlobalPreferences: params['importGlobalPreferences'] == true,
    )).toJson();
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'preferences-runtime-test-',
    );
    preferences = await PreferenceCommands.prepare(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('串行保存和读取等待实际后台应用，后继快照不被旧通知覆盖', () async {
    final applying = Completer<void>(), release = Completer<void>();
    final changes = <Map<String, dynamic>>[];
    final runtime = commands(
      onChanged: changes.add,
      applyBackgroundPolicy: (_) async {
        applying.complete();
        await release.future;
      },
    );
    final saving = runtime.invoke('settings.update', {
      'appearance': 'dark',
      'backgroundKeepAlive': false,
    });
    await applying.future;
    final second = runtime.invoke('settings.update', {'appearance': 'system'});
    var returned = false;
    final reading = runtime.read().then((settings) {
      returned = true;
      return settings;
    });
    await Future<void>.delayed(Duration.zero);
    expect(returned, isFalse);
    expect(changes, hasLength(1));
    release.complete();
    await Future.wait([saving, second]);
    expect((await reading)['appearance'], 'system');
    expect(changes.map((value) => value['appearance']), ['dark', 'system']);
  });

  test('偏好保存不创建原生镜像，后台回执未知可核验而不改写版本', () async {
    var rejected = true, observerRejected = false;
    final applied = <bool>[];
    final changes = <Map<String, dynamic>>[];
    final runtime = commands(
      onChanged: (settings) {
        changes.add(settings);
        if (observerRejected) throw StateError('观察者失败');
      },
      applyBackgroundPolicy: (enabled) async {
        applied.add(enabled);
        if (rejected) throw TimeoutException('平台回执未知');
      },
    );
    await expectLater(
      runtime.invoke('settings.update', {
        'appearance': 'dark',
        'backgroundKeepAlive': false,
      }),
      throwsA(
        errorCode('preferences_apply_unknown').having(
          (error) => error.details,
          'details',
          containsPair('saved', true),
        ),
      ),
    );
    expect(changes.single['appearance'], 'dark');
    expect(
      (await PreferenceCommands.prepare(directory))
          .current
          .values['appearance'],
      'dark',
    );
    final revision = preferences.current.revision;
    rejected = false;
    await runtime.reconcile();
    expect(applied, [false, false]);
    expect(preferences.current.revision, revision);
    expect(
      runtime.projectSnapshot({
        'settings': {'appearance': 'light'},
      })['settings']['appearance'],
      'dark',
    );
    await runtime.invoke('settings.update', {'fileViewMode': 'list'});
    expect(applied, [false, false]);
    observerRejected = true;
    await expectLater(
      runtime.invoke('settings.update', {'appearance': 'system'}),
      throwsA(errorCode('preferences_apply_unknown')),
    );
    expect(preferences.current.values['appearance'], 'system');
    observerRejected = false;
    await runtime.reconcile();
    expect(runtime.settings['appearance'], 'system');
    await runtime.invoke('settings.reset', {
      'keys': ['backgroundKeepAlive'],
    });
    expect(runtime.settings['backgroundKeepAlive'], isTrue);
    expect(applied, [false, false, false, true]);
    await runtime.invoke('settings.update', {'appearance': 'dark'});
    expect(applied, [false, false, false, true]);
  });

  test('导出保留设备读取失败且拒绝将畸形结果伪装成空备份', () async {
    var malformed = false;
    final runtime = commands(
      request: (command, _) async {
        expect(command, 'devices.list');
        if (malformed) {
          return {
            'devices': [null],
          };
        }
        throw const ApplicationCommandException('state_busy', '设备记录正在更新。');
      },
      onChanged: (_) => fail('只读导出不应发布偏好变化'),
    );
    await expectLater(
      runtime.invoke('settings.export', {}),
      throwsA(errorCode('state_busy')),
    );
    malformed = true;
    await expectLater(
      runtime.invoke('settings.export', {}),
      throwsA(errorCode('invalid_data')),
    );
  });

  test('lost record commit is reconciled from its atomic receipt without appending or applying preferences', () async {
    var lost = false, allocations = 0;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () {
        allocations++;
        return '11111111-1111-4111-8111-111111111111';
      },
      commitFile: (temporary, destination) async {
        await temporary.rename(destination.path);
        if (lost) {
          throw StateError('commit completed but acknowledgement unavailable');
        }
      },
    );
    final runtime = commands(request: importRequest(records));
    final input = metadata();
    final preview =
        await runtime.invoke('settings.import.preview', input) as Map;
    expect(preview['newRecords'], 1);
    expect(preview['globalChanges'], [
      {'key': 'appearance', 'current': 'light', 'imported': 'dark'},
    ]);
    expect(allocations, 0);
    lost = true;
    await expectLater(
      runtime.invoke('settings.import', input),
      throwsA(errorCode('preferences_import_unknown')),
    );
    expect(preferences.current.values['appearance'], 'light');
    final reopened = await DeviceRecordStore.open(directory: directory);
    expect(reopened.current.devices, hasLength(1));
    final checked =
        await runtime.invoke('settings.import.preview', input) as Map;
    expect(checked['alreadyImported'], true);
    expect(checked['newRecords'], 0);
    expect(checked['preferencesStatus'], 'needsReview');
    final duplicate = await runtime.invoke('settings.import', input) as Map;
    expect(duplicate['alreadyImported'], true);
    expect(allocations, 1);
    expect(preferences.current.values['appearance'], 'light');
  });

  test('restore with conflicting local save reports partial success without overwriting', () async {
    final other = await PreferenceCommands.prepare(directory);
    final runtime = commands(
      request: (command, values) async {
        expect(command, 'settings.import');
        expect((values['metadata'] as Map)['settings'], {'appearance': 'dark'});
        await other.update({'appearance': 'system'});
        return {
          'restored': 1,
          'authorizationRestored': false,
          'fingerprint': values['fingerprint'],
          'alreadyImported': false,
        };
      },
    );
    await expectLater(
      runtime.invoke('settings.import', metadata()),
      throwsA(errorCode('preferences_import_partial')),
    );
    expect(
      (await PreferenceCommands.prepare(directory))
          .current
          .values['appearance'],
      'system',
    );
  });

  test('preview admission preserves local settings by default and only explicit selection applies global changes', () async {
    final records = await DeviceRecordStore.open(directory: directory);
    var requests = 0;
    final runtime = commands(
      request: importRequest(records, onRequest: () => requests++),
    );
    await expectLater(
      runtime.invoke('settings.import', metadata({'privateKeyPem': 'secret'})),
      throwsA(errorCode('invalid_argument')),
    );
    expect(requests, 0);
    final input = metadata()..remove('importGlobalPreferences');
    await expectLater(
      runtime.invoke('settings.import', {...input, 'fingerprint': 'changed'}),
      throwsA(errorCode('invalid_import_preview')),
    );
    expect(requests, 0);
    final preview =
        await runtime.invoke('settings.import.preview', input) as Map;
    expect(preview['newRecords'], 1);
    final first = await runtime.invoke('settings.import', input) as Map;
    expect(first['preferencesStatus'], 'preserved');
    expect(preferences.current.values['appearance'], 'light');
    final second = metadata({'appearance': 'system'});
    await runtime.invoke('settings.import', second);
    expect(preferences.current.values['appearance'], 'system');
    expect(records.current.devices, hasLength(2));
  });
  test(
    'concurrent quality saves retain both device choices after restart',
    () async {
      final runtime = commands(request: (_, values) async => values);
      const first = '7b2a4273-cd2e-4aca-b86e-1e6d81170c81';
      const second = '8cd3c688-670c-46c1-b605-d140d9d8b4aa';
      await Future.wait([
        runtime.saveDeviceQuality(first, {'maxFps': 30, 'maxSize': 720}),
        runtime.saveDeviceQuality(second, {'maxFps': 60, 'maxSize': 1920}),
      ]);
      final restarted = await PreferenceCommands.prepare(directory);
      final quality = restarted.current.values['deviceQuality'] as Map;
      expect(quality[first]['maxFps'], 30);
      expect(quality[second]['maxSize'], 1920);
    },
  );
}
