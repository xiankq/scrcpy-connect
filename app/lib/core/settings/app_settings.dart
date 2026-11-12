import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/control/video_quality_policy.dart'
    show defaultVideoQuality, VideoQualityPolicy;
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_records_import.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/core/settings/preference_schema.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/settings_storage.dart';

const _devicePreferences = {'deviceQuality', 'deviceSettings', 'appOpenModes'};

/// 串行更新应用设置和导入元数据；持久化由偏好与设备记录所有者执行。
final class AppSettings implements MetadataManagement, SettingsManagement {
  AppSettings({
    required this.preferences,
    required this.records,
    required this.onDevicesImported,
    required this.onChanged,
    this.applyBackgroundPolicy,
    this.prepareImport,
    this.pauseReconnect,
    this.isDisposed,
  }) : _appliedBackground = preferences.current.values.backgroundKeepAlive;
  final SettingsStorage preferences;
  final DeviceRecordStorage records;
  final void Function(DeviceRecordsImport) onDevicesImported;
  final void Function(Preferences settings) onChanged;
  final Future<void> Function(bool enabled)? applyBackgroundPolicy;
  final Future<void> Function()? prepareImport;
  final Future<void> Function() Function()? pauseReconnect;
  final bool Function()? isDisposed;
  bool _appliedBackground;
  Future<void> _tail = Future<void>.value();

  static Future<SettingsStorage> prepare(Directory directory) =>
      SettingsStorage.open(
        directory: directory,
        schema: PreferenceSchema(
          defaults: {...preferenceDefaults, ...defaultVideoQuality},
        ),
      );

  Preferences get settings => preferences.current.values;
  int get revision => preferences.current.revision;

  @override
  Future<Preferences> read() => _tail.then((_) {
    _requireActive();
    return settings;
  });

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

  /// 与其他偏好更新共用保存队列，防止不同设备的画质设置互相覆盖。
  Future<void> saveDeviceQuality(
    String deviceId,
    VideoQualityPreferences quality,
  ) => _enqueue(() async {
    final devices = {...settings.deviceQuality, deviceId: quality};
    await preferences.update(
      PreferenceCodec.encodeChanges(PreferenceChanges(deviceQuality: devices)),
    );
    await _publishAndApply();
  });

  /// 设备遗忘成功后清理持久偏好；失败时仅重试本方法，不重复遗忘设备。
  Future<void> forgetDevicePreferences(String deviceId) => _enqueue(() async {
    try {
      final current = settings;
      final hasQuality = current.deviceQuality.containsKey(deviceId);
      final hasSettings = current.deviceSettings.containsKey(deviceId);
      final hasModes = current.appOpenModes.containsKey(deviceId);
      if (hasQuality || hasSettings || hasModes) {
        final changes = PreferenceChanges(
          deviceQuality: hasQuality
              ? (Map.of(current.deviceQuality)..remove(deviceId))
              : null,
          deviceSettings: hasSettings
              ? (Map.of(current.deviceSettings)..remove(deviceId))
              : null,
          appOpenModes: hasModes
              ? (Map.of(current.appOpenModes)..remove(deviceId))
              : null,
        );
        await preferences.update(PreferenceCodec.encodeChanges(changes));
      }
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

  @override
  Future<Preferences> update(
    PreferenceChanges changes, {
    int? expectedRevision,
  }) => _enqueue(() async {
    _requireActive();
    final encoded = PreferenceCodec.encodeChanges(changes);
    VideoQualityPolicy.validateSettings(encoded);
    await preferences.update(encoded, expectedRevision: expectedRevision);
    return _publishAndApply(
      forceBackgroundPolicy: changes.backgroundKeepAlive != null,
    );
  });

  @override
  Future<DeviceMetadata> exportMetadata() => _enqueue(() async {
    _requireActive();
    await records.reload();
    return records.exportMetadata(
      settings: {
        for (final entry in PreferenceCodec.encode(settings).entries)
          if (!_devicePreferences.contains(entry.key)) entry.key: entry.value,
      },
    );
  });

  @override
  Future<SettingsImportPreview> previewImport(DeviceMetadata metadata) =>
      _enqueue(() async {
        _requireActive();
        final imported = _importSettings(metadata);
        await preferences.reload();
        final receipt = await records.previewMetadata(metadata);
        final current = PreferenceCodec.encode(settings);
        return SettingsImportPreview(
          metadata: metadata,
          expectedRevision: revision,
          newRecords: receipt == null ? metadata.devices.length : 0,
          receipt: receipt,
          preferencesStatus: receipt == null
              ? null
              : _importStatus(
                  imported,
                  receipt.receipt.importGlobalPreferences,
                ),
          globalChanges: [
            for (final entry in imported.entries)
              if (current[entry.key] != entry.value)
                GlobalPreferenceChange(
                  key: entry.key,
                  current: current[entry.key],
                  imported: entry.value,
                ),
          ],
        );
      });

  Map<String, Object?> _importSettings(DeviceMetadata metadata) {
    final raw = metadata.document['settings'];
    if (raw is Map) {
      VideoQualityPolicy.validateSettings(Map<String, dynamic>.from(raw));
    }
    return preferences.schema.importSettings(raw ?? <String, Object?>{});
  }

  void _requireActive() {
    if (isDisposed?.call() ?? false) {
      throw const RequestFailure('disposed', '应用设置所有者已关闭。');
    }
  }

  @override
  Future<SettingsImportResult> importMetadata(
    SettingsImportPreview preview, {
    bool importGlobalPreferences = false,
  }) async {
    _requireActive();
    // 文件结构与偏好先校验，再撤销连接尝试。排空不能进入设置队列：
    // 连接任务本身可能正等待读取该队列中的设置。
    final imported = await _enqueue(() async {
      _requireActive();
      if (preview.expectedRevision < 1) {
        throw const PreferenceFailure('invalid_argument', '设置版本无效。');
      }
      _checkImportRevision(preview, importGlobalPreferences);
      return _importSettings(preview.metadata);
    });
    await prepareImport?.call();
    _requireActive();
    final resume = pauseReconnect?.call();
    try {
      return await _enqueue(
        () => _commitImport(
          preview,
          imported,
          importGlobalPreferences: importGlobalPreferences,
        ),
      );
    } finally {
      await resume?.call();
    }
  }

  Future<SettingsImportResult> _commitImport(
    SettingsImportPreview preview,
    Map<String, Object?> imported, {
    required bool importGlobalPreferences,
  }) async {
    _requireActive();
    final metadata = preview.metadata;
    final fingerprint = metadata.fingerprint;
    final importGlobal = importGlobalPreferences;
    final expected = preview.expectedRevision;
    _checkImportRevision(preview, importGlobal);
    late final DeviceRecordsImport importedRecords;
    try {
      importedRecords = await records.importMetadata(
        metadata,
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
      return SettingsImportResult(
        records: importedRecords,
        preferencesStatus: _importStatus(
          imported,
          importedRecords.receipt.importGlobalPreferences,
        ),
      );
    }
    if (!importGlobal || imported.isEmpty) {
      return SettingsImportResult(
        records: importedRecords,
        preferencesStatus: ImportPreferencesStatus.preserved,
      );
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
    return SettingsImportResult(
      records: importedRecords,
      preferencesStatus: ImportPreferencesStatus.imported,
    );
  }

  void _checkImportRevision(SettingsImportPreview preview, bool importGlobal) {
    if (importGlobal && preview.expectedRevision != revision) {
      throw const PreferenceFailure(
        'preferences_conflict',
        '设置已被其他操作更新，请重新预览。',
      );
    }
  }

  ImportPreferencesStatus _importStatus(
    Map<String, Object?> imported,
    bool importGlobal,
  ) {
    if (!importGlobal) return ImportPreferencesStatus.preserved;
    final current = PreferenceCodec.encode(settings);
    return imported.entries.every((entry) => current[entry.key] == entry.value)
        ? ImportPreferencesStatus.matchesCurrent
        : ImportPreferencesStatus.needsReview;
  }

  Future<Preferences> _publishAndApply({
    bool forceBackgroundPolicy = false,
  }) async {
    final saved = settings;
    try {
      onChanged(saved);
      final background = saved.backgroundKeepAlive;
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
