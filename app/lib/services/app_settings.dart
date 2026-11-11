import 'package:scrcpy_connect/models/device_records_import.dart';

import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/services/settings_storage.dart';
import 'package:scrcpy_connect/models/device_metadata.dart';
import 'package:scrcpy_connect/services/device_record_storage.dart';
import 'package:scrcpy_connect/models/preference_schema.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/video_quality_policy.dart'
    show defaultVideoQuality;

const _devicePreferences = {'deviceQuality', 'deviceSettings', 'appOpenModes'};

/// 串行更新应用设置和导入元数据；持久化由偏好与设备记录所有者执行。
final class AppSettings {
  AppSettings({
    required this.preferences,
    required this.records,
    required this.onDevicesImported,
    required this.onChanged,
    this.applyBackgroundPolicy,
  }) : _appliedBackground =
           preferences.current.values['backgroundKeepAlive'] == true;
  final SettingsStorage preferences;
  final DeviceRecordStorage records;
  final void Function(DeviceRecordsImport) onDevicesImported;
  final void Function(Map<String, dynamic> settings) onChanged;
  final Future<void> Function(bool enabled)? applyBackgroundPolicy;
  bool _appliedBackground;
  Future<void> _tail = Future<void>.value();

  static Future<SettingsStorage> prepare(Directory directory) =>
      SettingsStorage.open(
        directory: directory,
        schema: PreferenceSchema(
          defaults: {...preferenceDefaults, ...defaultVideoQuality},
        ),
      );

  Map<String, dynamic> get settings => preferences.current.toMap();
  int get revision => preferences.current.revision;

  Future<Map<String, dynamic>> read() => _tail.then((_) => settings);

  Map<String, dynamic> projectSnapshot(Map<String, dynamic> native) => {
    ...native,
    'settings': settings,
  };
  Map<String, dynamic> projectEvent(Map<String, dynamic> native) =>
      (native['type'] ?? native['kind']) == 'settings.changed'
      ? {...native, 'data': settings}
      : native;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _tail.then((_) async {
      try {
        return await action();
      } on PreferenceFailure catch (error) {
        throw RequestFailure(error.code, error.message, error.details);
      } on DeviceRecordsFailure catch (error) {
        throw RequestFailure(error.code, error.message, error.details);
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  /// 与其他偏好命令共用保存队列，防止不同设备的画质设置互相覆盖。
  Future<void> saveDeviceQuality(
    String deviceId,
    Map<String, dynamic> quality,
  ) => _enqueue(() async {
    final devices = Map<String, Object?>.from(settings['deviceQuality'] as Map);
    devices[deviceId] = {
      for (final key in qualityKeys)
        if (quality.containsKey(key)) key: quality[key],
    };
    await preferences.update({'deviceQuality': devices});
    await _publishAndApply();
  });

  /// 设备遗忘成功后清理持久偏好；失败时仅重试本方法，不重复遗忘设备。
  Future<void> forgetDevicePreferences(String deviceId) => _enqueue(() async {
    try {
      final current = settings;
      final changes = <String, Object?>{};
      for (final key in _devicePreferences) {
        final devices = Map<String, Object?>.from(current[key] as Map);
        if (devices.containsKey(deviceId)) {
          devices.remove(deviceId);
          changes[key] = devices;
        }
      }
      if (changes.isNotEmpty) await preferences.update(changes);
    } catch (error) {
      // 存储层明确区分提交未知；未分类的文件系统错误也不能宣称没有提交。
      final unknown =
          error is! PreferenceFailure ||
          error.code == 'preferences_write_unknown';
      throw RequestFailure(
        unknown ? 'preferences_cleanup_unknown' : 'preferences_cleanup_partial',
        unknown ? '设备已遗忘，偏好清理结果未知，请重新读取后核对。' : '设备已遗忘，偏好尚未清理，可单独重试偏好清理。',
        {
          'deviceId': deviceId,
          'deviceForgotten': true,
          'preferencesSaved': unknown ? 'unknown' : false,
          'cause': error is PreferenceFailure ? error.code : 'preferences_io',
          if (error is PreferenceFailure && error.details.isNotEmpty)
            'preferenceFailure': error.details,
        },
      );
    }
    try {
      // 重复清理只发布已保存的快照，不重复设备遗忘或原生业务调用。
      await _publishAndApply();
    } catch (error) {
      throw RequestFailure(
        'preferences_apply_unknown',
        '设备已遗忘且偏好已清理，应用状态通知或后台策略尚未确认。',
        {
          if (error is PreferenceFailure) ...error.details,
          'deviceId': deviceId,
          'deviceForgotten': true,
          'preferencesSaved': true,
          'saved': true,
          'applied': 'unknown',
          'revision': revision,
        },
      );
    }
  });

  Future<Map<String, dynamic>> update(Map<String, dynamic> parameters) =>
      _enqueue(() async {
        final changes = {...parameters}..remove('expectedRevision');
        await preferences.update(
          changes,
          expectedRevision: _revision(parameters),
        );
        return await _publishAndApply(
          forceBackgroundPolicy: changes.containsKey('backgroundKeepAlive'),
        );
      });

  Future<Map<String, dynamic>> reset(Map<String, dynamic> parameters) =>
      _enqueue(() async {
        final keys = parameters['keys'];
        if (keys != null &&
            (keys is! List || keys.any((key) => key is! String))) {
          throw const PreferenceFailure('invalid_argument', '重置设置项无效。');
        }
        await preferences.reset(
          keys: keys == null ? null : Set<String>.from(keys as List),
          expectedRevision: _revision(parameters),
        );
        return await _publishAndApply(
          forceBackgroundPolicy:
              keys == null || (keys as List).contains('backgroundKeepAlive'),
        );
      });

  Future<Map<String, dynamic>> exportMetadata() => _enqueue(() async {
    await records.reload();
    return records.exportMetadata(
      settings: {
        for (final entry in settings.entries)
          if (!_devicePreferences.contains(entry.key)) entry.key: entry.value,
      },
    );
  });

  Future<Map<String, dynamic>> previewImport(Map<String, dynamic> parameters) =>
      _enqueue(() async {
        final metadata = DeviceMetadata.parse(parameters['metadata']);
        final imported = preferences.schema.importSettings(
          metadata.document['settings'] ?? <String, Object?>{},
        );
        await preferences.reload();
        final preview = await records.previewMetadata(metadata.document);
        return {
          ...preview,
          'expectedRevision': revision,
          if (preview['receipt'] is Map)
            'preferencesStatus': _importStatus(
              imported,
              (preview['receipt'] as Map)['importGlobalPreferences'] == true,
            ),
          'globalChanges': [
            for (final entry in imported.entries)
              if (settings[entry.key] != entry.value)
                {
                  'key': entry.key,
                  'current': settings[entry.key],
                  'imported': entry.value,
                },
          ],
        };
      });

  Future<Map<String, dynamic>> importMetadata(
    Map<String, dynamic> parameters,
  ) => _enqueue(() async {
    final metadata = DeviceMetadata.parse(parameters['metadata']);
    final imported = preferences.schema.importSettings(
      metadata.document['settings'] ?? <String, Object?>{},
    );
    final fingerprint = parameters['fingerprint'];
    if (fingerprint is! String || fingerprint != metadata.fingerprint) {
      throw const PreferenceFailure(
        'invalid_import_preview',
        '请先预览当前文件，再确认导入。',
      );
    }
    final importGlobal = parameters['importGlobalPreferences'] == true;
    final expected = _revision(parameters) ?? revision;
    if (importGlobal && expected != revision) {
      throw const PreferenceFailure(
        'preferences_conflict',
        '设置已被其他操作更新，请重新预览。',
      );
    }
    late final DeviceRecordsImport importedRecords;
    try {
      importedRecords = await records.importMetadata(
        metadata.document,
        expectedFingerprint: fingerprint,
        importGlobalPreferences: importGlobal,
      );
      if (!importedRecords.alreadyImported) {
        onDevicesImported(importedRecords);
      }
    } catch (error) {
      if (error is DeviceRecordsFailure &&
          (error.code.startsWith('invalid_') ||
              error.code == 'records_too_large' ||
              error.code == 'import_history_full')) {
        rethrow;
      }
      throw PreferenceFailure(
        'preferences_import_unknown',
        '导入结果尚待核对，请重新预览同一文件；不会自动追加设备记录。',
        {
          'fingerprint': fingerprint,
          'preferencesSaved': false,
          'devicesRestored': 'unknown',
          'authorizationRestored': false,
        },
      );
    }
    final restored = importedRecords.toJson();
    if (importedRecords.alreadyImported) {
      await preferences.reload();
      return {
        ...restored,
        'preferencesStatus': _importStatus(
          imported,
          importedRecords.receipt.importGlobalPreferences,
        ),
      };
    }
    if (!importGlobal || imported.isEmpty) {
      return {...restored, 'preferencesStatus': 'preserved'};
    }
    try {
      await preferences.update(imported, expectedRevision: expected);
    } catch (error) {
      final unknown =
          error is! PreferenceFailure ||
          error.code == 'preferences_write_unknown';
      throw PreferenceFailure(
        unknown ? 'preferences_import_unknown' : 'preferences_import_partial',
        unknown
            ? '设备记录已导入，全局偏好提交结果待核对。请重新预览同一文件，勿重复导入。'
            : '设备记录已导入，全局偏好尚未保存。请检查当前设置。',
        {
          'fingerprint': fingerprint,
          'preferencesSaved': unknown ? 'unknown' : false,
          'devicesRestored': restored,
          'authorizationRestored': false,
          'cause': error is PreferenceFailure ? error.code : 'preferences_io',
          if (error is PreferenceFailure && error.details.isNotEmpty)
            'preferenceFailure': error.details,
        },
      );
    }
    await _publishAndApply(forceBackgroundPolicy: true);
    return {...restored, 'preferencesStatus': 'imported'};
  });

  String _importStatus(Map<String, Object?> imported, bool importGlobal) {
    if (!importGlobal) return 'preserved';
    final current = settings;
    return imported.entries.every((entry) => current[entry.key] == entry.value)
        ? 'matchesCurrent'
        : 'needsReview';
  }

  int? _revision(Map<String, dynamic> parameters) {
    final value = parameters['expectedRevision'];
    if (value == null) return null;
    if (value is! int || value < 1) {
      throw const PreferenceFailure('invalid_argument', '设置版本无效。');
    }
    return value;
  }

  Future<Map<String, dynamic>> _publishAndApply({
    bool forceBackgroundPolicy = false,
  }) async {
    final saved = settings;
    try {
      onChanged(saved);
      final background = saved['backgroundKeepAlive'] == true;
      if (forceBackgroundPolicy || background != _appliedBackground) {
        await applyBackgroundPolicy?.call(background);
        _appliedBackground = background;
      }
    } catch (_) {
      throw PreferenceFailure(
        'preferences_apply_unknown',
        '设置已保存，当前设备应用结果尚未确认。',
        {'saved': true, 'applied': 'unknown', 'revision': revision},
      );
    }
    return saved;
  }

  /// 重新附着或回执不确定后重新应用持久快照；不重试设备恢复，也不改写偏好 revision。
  Future<void> reconcile() => _enqueue(() async {
    await preferences.reload();
    await _publishAndApply(forceBackgroundPolicy: true);
  });
}
