import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_metadata_transfer.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_records_import.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/settings_storage.dart';

void main() {
  test('偏好已保存后关闭不再启动后台策略，回执保留已保存但应用未知', () async {
    final fixture = await _Fixture.open();
    var applied = 0;
    fixture.onSettingsChanged = () => fixture.disposed = true;
    fixture.applyBackground = (_) async => applied++;
    await expectLater(
      fixture.settings.update(PreferenceChanges(backgroundKeepAlive: true)),
      throwsA(
        isA<RequestFailure>()
            .having((e) => e.code, 'code', 'preferences_apply_unknown')
            .having((e) => (e.details as Map)['saved'], 'saved', true)
            .having((e) => (e.details as Map)['applied'], 'applied', 'unknown'),
      ),
    );
    expect(fixture.settings.settings.backgroundKeepAlive, isTrue);
    expect(applied, 0);
    await expectLater(fixture.settings.reconcile(), _failure('disposed'));
    await expectLater(
      fixture.settings.forgetDevicePreferences('phone'),
      _failure('disposed'),
    );
  });

  test('真实导入覆盖整次冻结，同一文件只追加一次且不恢复设备授权', () async {
    final fixture = await _Fixture.open();
    fixture.prepare = () async {
      await fixture.settings.read();
      fixture.steps.add('drained');
    };
    final preview = await fixture.settings.previewImport(_document());
    final result = await fixture.settings.importMetadata(
      preview,
      importGlobalPreferences: true,
    );
    expect(result.preferencesStatus, ImportPreferencesStatus.imported);
    expect(result.records.authorizationRestored, isFalse);
    expect(fixture.steps, ['drained', 'hold', 'devices', 'settings', 'resume']);
    final record = fixture.records.current.devices.single;
    expect(record.status, 'unauthorized');
    expect(record.autoReconnect, isFalse);
    expect(fixture.settings.settings.appearance, Appearance.dark);
    final revision = fixture.settings.revision;
    final repeated = await fixture.settings.previewImport(_document());
    expect(repeated.alreadyImported, isTrue);
    final verified = await fixture.settings.importMetadata(
      repeated,
      importGlobalPreferences: true,
    );
    expect(verified.records.alreadyImported, isTrue);
    expect(verified.preferencesStatus, ImportPreferencesStatus.matchesCurrent);
    expect(fixture.settings.revision, revision);
    expect(fixture.records.current.devices.single.id, record.id);
  });

  test('排空连接不占设置队列，排空期间偏好变化在写设备前拒绝旧版本', () async {
    final fixture = await _Fixture.open();
    final preparing = Completer<void>(), drained = Completer<void>();
    addTearDown(() {
      if (!drained.isCompleted) drained.complete();
    });
    fixture.prepare = () async {
      await fixture.settings.read();
      preparing.complete();
      await drained.future;
    };
    final preview = await fixture.settings.previewImport(_document());
    final importing = expectLater(
      fixture.settings.importMetadata(preview, importGlobalPreferences: true),
      _failure('preferences_conflict'),
    );
    await preparing.future;
    await fixture.settings.update(PreferenceChanges(appearance: .light));
    drained.complete();
    await importing;
    expect(fixture.records.current.devices, isEmpty);
    expect(fixture.steps, ['settings', 'hold', 'resume']);
  });

  test('设备保存回执未知后核对同一账本，不追加设备也不重放全局偏好', () async {
    var loseReceipt = false;
    final fixture = await _Fixture.open(
      commitFile: (temporary, destination) async {
        await temporary.rename(destination.path);
        if (loseReceipt) {
          loseReceipt = false;
          throw StateError('record receipt lost');
        }
      },
    );
    final preview = await fixture.settings.previewImport(_document());
    loseReceipt = true;
    await expectLater(
      fixture.settings.importMetadata(preview, importGlobalPreferences: true),
      _failure('preferences_import_unknown'),
    );
    expect(fixture.steps, ['hold', 'resume']);
    final verified = await fixture.settings.previewImport(_document());
    expect(verified.alreadyImported, isTrue);
    final original = verified.receipt!.receipt.deviceIds.single;
    final result = await fixture.settings.importMetadata(
      verified,
      importGlobalPreferences: true,
    );
    expect(result.preferencesStatus, ImportPreferencesStatus.needsReview);
    expect(fixture.records.current.devices.single.id, original);
    expect(fixture.settings.settings.appearance, isNot(Appearance.dark));
    expect(fixture.steps, ['hold', 'resume', 'hold', 'devices', 'resume']);
  });

  test('设备已保存而偏好失败时保留部分结果，重试仅核对已保存记录', () async {
    final fixture = await _Fixture.open();
    final preferences = File('${fixture.directory.path}/preferences.json');
    final previous = await preferences.readAsBytes();
    fixture.onImported = preferences.deleteSync;
    final preview = await fixture.settings.previewImport(_document());
    await expectLater(
      fixture.settings.importMetadata(preview, importGlobalPreferences: true),
      throwsA(
        isA<RequestFailure>()
            .having((e) => e.code, 'code', 'preferences_import_partial')
            .having(
              (e) => (e.details as Map)['preferencesSaved'],
              'saved',
              false,
            )
            .having(
              (e) => (e.details as Map)['authorizationRestored'],
              'authorization',
              false,
            ),
      ),
    );
    final original = fixture.records.current.devices.single.id;
    expect(fixture.steps, ['hold', 'devices', 'resume']);
    await preferences.writeAsBytes(previous, flush: true);
    fixture.onImported = () {};
    final verified = await fixture.settings.previewImport(_document());
    final result = await fixture.settings.importMetadata(
      verified,
      importGlobalPreferences: true,
    );
    expect(result.preferencesStatus, ImportPreferencesStatus.needsReview);
    expect(fixture.records.current.devices.single.id, original);
    expect(fixture.settings.settings.appearance, isNot(Appearance.dark));
  });

  test('迁移关闭等待原连接排空，排空后的迟到操作不能保存或冻结连接', () async {
    final fixture = await _Fixture.open();
    final preparing = Completer<void>(), drained = Completer<void>();
    addTearDown(() {
      if (!drained.isCompleted) drained.complete();
    });
    fixture.prepare = () async {
      preparing.complete();
      await drained.future;
    };
    final preview = await fixture.settings.previewImport(_document());
    final importing = expectLater(
      fixture.settings.importMetadata(preview),
      _failure('disposed'),
    );
    await preparing.future;
    var closed = false;
    final closing = fixture.transfer.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    drained.complete();
    await Future.wait([closing, importing]);
    expect(fixture.records.current.devices, isEmpty);
    expect(fixture.steps, isEmpty);
  });

  test('关闭等待已受理的整次提交，提交函数不能带出其冻结作用域', () async {
    final fixture = await _Fixture.open();
    final saved = Completer<void>(), finished = Completer<void>();
    addTearDown(() {
      if (!finished.isCompleted) finished.complete();
    });
    late Future<DeviceRecordsImport> Function() escaped;
    final importing = fixture.transfer.import(
      _document(),
      importGlobalPreferences: false,
      apply: (commit) async {
        escaped = commit;
        final first = commit();
        expect(commit(), same(first));
        final result = await first;
        saved.complete();
        await finished.future;
        return result;
      },
    );
    await saved.future;
    var closed = false;
    final closing = fixture.transfer.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(fixture.steps, ['hold', 'devices']);
    finished.complete();
    await Future.wait([importing, closing]);
    expect(fixture.steps, ['hold', 'devices', 'resume']);
    expect(escaped, _failure('disposed'));
    expect(fixture.records.current.devices, hasLength(1));
  });

  test('冻结释放失败保留原租约，关闭仅重试释放而不重复设备保存', () async {
    final fixture = await _Fixture.open();
    final failure = StateError('release unconfirmed');
    var allowed = false, releases = 0;
    addTearDown(() => allowed = true);
    fixture.release = () async {
      releases++;
      if (!allowed) throw failure;
    };
    await expectLater(
      fixture.transfer.import(
        _document(),
        importGlobalPreferences: false,
        apply: (commit) => commit(),
      ),
      throwsA(same(failure)),
    );
    final original = fixture.records.current.devices.single.id;
    await expectLater(fixture.transfer.close(), throwsA(same(failure)));
    expect(releases, 2);
    allowed = true;
    await fixture.transfer.close();
    await fixture.transfer.close();
    expect(releases, 3);
    expect(fixture.records.current.devices.single.id, original);
    expect(fixture.steps.where((step) => step == 'devices'), hasLength(1));
  });
}

Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((e) => e.code, 'code', code));

DeviceMetadata _document() => DeviceMetadata.parse({
  'format': 'scrcpy-connect-metadata',
  'version': 1,
  'devices': [
    {
      'name': 'Restored phone',
      'address': '192.0.2.1',
      'port': 5555,
      'transport': 'tcp',
    },
  ],
  'settings': {'appearance': 'dark'},
});

final class _Fixture {
  _Fixture(this.directory, this.records, this.storage);
  final Directory directory;
  final DeviceRecordStorage records;
  final SettingsStorage storage;
  final steps = <String>[];
  Future<void> Function() prepare = () async {};
  Future<void> Function() release = () async {};
  void Function() onImported = () {};
  void Function() onSettingsChanged = () {};
  Future<void> Function(bool) applyBackground = (_) async {};
  bool disposed = false;
  late final transfer = DeviceMetadataTransfer(
    records: records,
    prepareImport: () => prepare(),
    holdReconnect: () {
      steps.add('hold');
      return () async {
        steps.add('resume');
        await release();
      };
    },
    onImported: () {
      steps.add('devices');
      onImported();
    },
    isDisposed: () => disposed,
  );
  late final settings = AppSettings(
    preferences: storage,
    metadata: transfer,
    onChanged: (_) {
      steps.add('settings');
      onSettingsChanged();
    },
    applyBackgroundPolicy: (enabled) => applyBackground(enabled),
    isDisposed: () => disposed,
  );

  static Future<_Fixture> open({DeviceRecordsCommit? commitFile}) async {
    final temporary = await Directory.systemTemp.createTemp('metadata-import-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    addTearDown(() => temporary.delete(recursive: true));
    final fixture = _Fixture(
      directory,
      await DeviceRecordStorage.open(
        directory: directory,
        commitFile: commitFile,
      ),
      await AppSettings.prepare(directory),
    );
    addTearDown(fixture.transfer.close);
    return fixture;
  }
}
