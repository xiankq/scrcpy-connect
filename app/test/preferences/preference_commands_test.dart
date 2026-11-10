import 'package:scrcpy_connect/models/device_records_import.dart';

import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/stores/settings_store.dart';
import 'package:scrcpy_connect/stores/device_store.dart';
import 'package:scrcpy_connect/models/device_metadata.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

TypeMatcher<RequestFailure> errorCode(String code) =>
    isA<RequestFailure>().having((error) => error.code, 'code', code);
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
  late SettingsStore preferences;
  late DeviceStore records;
  AppSettings commands({
    DeviceStore? deviceRecords,
    void Function(DeviceRecordsImport)? onDevicesImported,
    void Function(Map<String, dynamic>)? onChanged,
    Future<void> Function(bool)? applyBackgroundPolicy,
  }) => AppSettings(
    preferences: preferences,
    records: deviceRecords ?? records,
    onDevicesImported: onDevicesImported ?? (_) {},
    onChanged: onChanged ?? (_) {},
    applyBackgroundPolicy: applyBackgroundPolicy,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'preferences-runtime-test-',
    );
    preferences = await AppSettings.prepare(directory);
    records = await DeviceStore.open(directory: directory);
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
    final saving = runtime.update({
      'appearance': 'dark',
      'backgroundKeepAlive': false,
    });
    await applying.future;
    final second = runtime.update({'appearance': 'system'});
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
      runtime.update({'appearance': 'dark', 'backgroundKeepAlive': false}),
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
      (await AppSettings.prepare(directory)).current.values['appearance'],
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
    await runtime.update({'fileViewMode': 'list'});
    expect(applied, [false, false]);
    observerRejected = true;
    await expectLater(
      runtime.update({'appearance': 'system'}),
      throwsA(errorCode('preferences_apply_unknown')),
    );
    expect(preferences.current.values['appearance'], 'system');
    observerRejected = false;
    await runtime.reconcile();
    expect(runtime.settings['appearance'], 'system');
    await runtime.reset({
      'keys': ['backgroundKeepAlive'],
    });
    expect(runtime.settings['backgroundKeepAlive'], isTrue);
    expect(applied, [false, false, false, true]);
    await runtime.update({'appearance': 'dark'});
    expect(applied, [false, false, false, true]);
  });

  test('导出读取持久设备元数据，损坏账本不能伪装成空备份', () async {
    final device = await records.add(
      address: 'phone.local',
      port: 5555,
      name: 'Phone',
    );
    final runtime = commands(onChanged: (_) => fail('只读导出不应发布偏好变化'));
    final exported = await runtime.exportMetadata();
    final document = exported['metadata'] as Map;
    final saved = (document['devices'] as List).single as Map;
    expect(saved['name'], 'Phone');
    expect(saved['address'], 'phone.local');
    expect(saved, isNot(contains('id')));
    expect(saved, isNot(contains('status')));
    expect(saved, isNot(contains('identityFingerprint')));
    expect(document['settings'], isNot(contains('deviceQuality')));
    expect(records.current.find(device.id), isNotNull);
    await records.file.writeAsString('{');
    await expectLater(
      runtime.exportMetadata(),
      throwsA(errorCode('records_corrupt')),
    );
  });

  for (final failure in ['record commit', 'device publication']) {
    test(
      'lost $failure is reconciled without appending or applying preferences',
      () async {
        var lost = false, allocations = 0, publications = 0;
        final records = await DeviceStore.open(
          directory: directory,
          idFactory: () {
            allocations++;
            return '11111111-1111-4111-8111-111111111111';
          },
          commitFile: (temporary, destination) async {
            await temporary.rename(destination.path);
            if (lost && failure == 'record commit') {
              throw StateError(
                'commit completed but acknowledgement unavailable',
              );
            }
          },
        );
        final runtime = commands(
          deviceRecords: records,
          onDevicesImported: (_) {
            publications++;
            if (lost) {
              throw StateError(
                'device publication acknowledgement unavailable',
              );
            }
          },
        );
        final input = metadata();
        final preview = await runtime.previewImport(input);
        expect(preview['newRecords'], 1);
        expect(preview['globalChanges'], [
          {'key': 'appearance', 'current': 'light', 'imported': 'dark'},
        ]);
        expect(allocations, 0);
        lost = true;
        await expectLater(
          runtime.importMetadata(input),
          throwsA(errorCode('preferences_import_unknown')),
        );
        expect(preferences.current.values['appearance'], 'light');
        final reopened = await DeviceStore.open(directory: directory);
        expect(reopened.current.devices, hasLength(1));
        final checked = await runtime.previewImport(input);
        expect(checked['alreadyImported'], true);
        expect(checked['newRecords'], 0);
        expect(checked['preferencesStatus'], 'needsReview');
        final duplicate = await runtime.importMetadata(input);
        expect(duplicate['alreadyImported'], true);
        expect(allocations, 1);
        expect(preferences.current.values['appearance'], 'light');
        expect(publications, failure == 'record commit' ? 0 : 1);
      },
    );
  }

  test('restore with conflicting local save reports partial success without overwriting', () async {
    final other = await AppSettings.prepare(directory);
    var competing = false;
    final records = await DeviceStore.open(
      directory: directory,
      commitFile: (temporary, destination) async {
        await temporary.rename(destination.path);
        if (competing) await other.update({'appearance': 'system'});
      },
    );
    competing = true;
    final runtime = commands(deviceRecords: records);
    await expectLater(
      runtime.importMetadata(metadata()),
      throwsA(errorCode('preferences_import_partial')),
    );
    expect(records.current.devices, hasLength(1));
    expect(
      (await AppSettings.prepare(directory)).current.values['appearance'],
      'system',
    );
  });

  test('preview admission preserves local settings by default and only explicit selection applies global changes', () async {
    var allocations = 0;
    final records = await DeviceStore.open(
      directory: directory,
      idFactory: () =>
          '00000000-0000-4000-8000-${(++allocations).toString().padLeft(12, '0')}',
    );
    final runtime = commands(deviceRecords: records);
    await expectLater(
      runtime.importMetadata(metadata({'privateKeyPem': 'secret'})),
      throwsA(errorCode('invalid_argument')),
    );
    expect(allocations, 0);
    final input = metadata()..remove('importGlobalPreferences');
    await expectLater(
      runtime.importMetadata({...input, 'fingerprint': 'changed'}),
      throwsA(errorCode('invalid_import_preview')),
    );
    expect(allocations, 0);
    final preview = await runtime.previewImport(input);
    expect(preview['newRecords'], 1);
    final first = await runtime.importMetadata(input);
    expect(first['preferencesStatus'], 'preserved');
    expect(preferences.current.values['appearance'], 'light');
    final second = metadata({'appearance': 'system'});
    await runtime.importMetadata(second);
    expect(preferences.current.values['appearance'], 'system');
    expect(records.current.devices, hasLength(2));
  });
  test(
    'concurrent quality saves retain both device choices after restart',
    () async {
      final runtime = commands();
      const first = '7b2a4273-cd2e-4aca-b86e-1e6d81170c81';
      const second = '8cd3c688-670c-46c1-b605-d140d9d8b4aa';
      await Future.wait([
        runtime.saveDeviceQuality(first, {'maxFps': 30, 'maxSize': 720}),
        runtime.saveDeviceQuality(second, {'maxFps': 60, 'maxSize': 1920}),
      ]);
      final restarted = await AppSettings.prepare(directory);
      final quality = restarted.current.values['deviceQuality'] as Map;
      expect(quality[first]['maxFps'], 30);
      expect(quality[second]['maxSize'], 1920);
    },
  );
}
