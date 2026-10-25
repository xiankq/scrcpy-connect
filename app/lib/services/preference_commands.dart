import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/stores/preference_store.dart';
import 'package:scrcpy_connect/models/preference_schema.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/services/media/video_quality_policy.dart'
    show defaultVideoQuality;

typedef PreferenceDeviceRequest = Future<dynamic> Function(
  String command,
  Map<String, dynamic> parameters,
);

/// 应用持有唯一偏好快照；业务所有者读取此快照，再向能力传入当次明确选项。
/// [request] 只用于设备记录导入与导出，不向原生安装第二份产品设置。
final class PreferenceCommands {
  PreferenceCommands({
    required this.preferences,
    required this.request,
    required this.onChanged,
    this.applyBackgroundPolicy,
  }) : _appliedBackground =
           preferences.current.values['backgroundKeepAlive'] == true;
  final PreferenceStore preferences;
  final PreferenceDeviceRequest request;
  final void Function(Map<String, dynamic> settings) onChanged;
  final Future<void> Function(bool enabled)? applyBackgroundPolicy;
  bool _appliedBackground;
  Future<void> _tail = Future<void>.value();

  static Future<PreferenceStore> prepare(Directory directory) =>
      PreferenceStore.open(
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

  bool handles(String command) => const {
    'settings.get',
    'settings.update',
    'settings.reset',
    'settings.export',
    'settings.import',
  }.contains(command);

  Future<dynamic> invoke(String command, Map<String, dynamic> parameters) {
    final operation = _tail.then((_) => _invoke(command, parameters));
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  /// 与其他偏好命令共用保存队列，防止不同设备的画质设置互相覆盖。
  Future<void> saveDeviceQuality(
    String deviceId,
    Map<String, dynamic> quality,
  ) {
    final operation = _tail.then((_) async {
      try {
        final current = preferences.current.toMap();
        final devices = Map<String, Object?>.from(
          current['deviceQuality'] as Map,
        );
        devices[deviceId] = {
          for (final key in qualityKeys)
            if (quality.containsKey(key)) key: quality[key],
        };
        await preferences.update({'deviceQuality': devices});
        await _publishAndApply();
      } on PreferenceFailure catch (error) {
        throw ApplicationCommandException(
          error.code,
          error.message,
          error.details,
        );
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  /// 设备遗忘成功后清理持久偏好；失败时仅重试本方法，不重复遗忘设备。
  Future<void> forgetDevicePreferences(String deviceId) {
    final operation = _tail.then((_) async {
      try {
        final current = preferences.current.toMap();
        final quality = Map<String, Object?>.from(
          current['deviceQuality'] as Map,
        );
        final deviceSettings = Map<String, Object?>.from(
          current['deviceSettings'] as Map,
        );
        if (quality.containsKey(deviceId) ||
            deviceSettings.containsKey(deviceId)) {
          quality.remove(deviceId);
          deviceSettings.remove(deviceId);
          await preferences.update({
            'deviceQuality': quality,
            'deviceSettings': deviceSettings,
          });
        }
      } catch (error) {
        // 存储层明确区分提交未知；未分类的文件系统错误也不能宣称没有提交。
        final unknown =
            error is! PreferenceFailure ||
            error.code == 'preferences_write_unknown';
        throw ApplicationCommandException(
          unknown
              ? 'preferences_cleanup_unknown'
              : 'preferences_cleanup_partial',
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
        throw ApplicationCommandException(
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
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<dynamic> _invoke(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    try {
      switch (command) {
        case 'settings.get':
          return settings;
        case 'settings.update':
          final changes = {...parameters}..remove('expectedRevision');
          await preferences.update(
            changes,
            expectedRevision: _revision(parameters),
          );
          return await _publishAndApply(
            forceBackgroundPolicy: changes.containsKey('backgroundKeepAlive'),
          );
        case 'settings.reset':
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
        case 'settings.export':
          final facts = await request('devices.list', {});
          if (facts is! Map ||
              facts['devices'] is! List ||
              (facts['devices'] as List).any((device) => device is! Map)) {
            throw const PreferenceFailure('invalid_data', '设备记录读取结果无效。');
          }
          return {
            'metadata': {
              'format': 'scrcpy-connect-metadata',
              'version': 1,
              // 兼容 v1 的显式白名单；事实接口新增字段不会扩大备份内容。
              'devices': [
                for (final device in facts['devices'] as List)
                  {
                    for (final key in const [
                      'name',
                      'address',
                      'port',
                      'transport',
                      'guid',
                      'serial',
                      'model',
                      'androidVersion',
                      'apiLevel',
                    ])
                      key: (device as Map)[key],
                  },
              ],
              'settings': settings,
            },
          };
        case 'settings.import':
          final metadata = parameters['metadata'];
          if (metadata is! Map ||
              metadata.keys.any((key) => key is! String) ||
              metadata['format'] != 'scrcpy-connect-metadata' ||
              metadata['version'] != 1) {
            throw const PreferenceFailure('invalid_data', '设备记录格式或版本不受支持。');
          }
          // 恢复设备前先核验全部偏好；导入时清空设备偏好，因为设备记录所有者会分配新 ID。
          final imported = preferences.schema.importSettings(
            metadata['settings'],
          );
          final expected = _revision(parameters) ?? revision;
          if (expected != revision) {
            throw const PreferenceFailure(
              'preferences_conflict',
              '设置已被其他操作更新，请重新检查。',
            );
          }
          dynamic restored;
          try {
            restored = await request(command, {
              'metadata': <String, dynamic>{
                ...Map<String, dynamic>.from(metadata),
                'settings': <String, Object?>{},
              },
            });
          } catch (error) {
            if (error is ApplicationCommandException &&
                error.code.startsWith('invalid_')) {
              rethrow;
            }
            throw const PreferenceFailure(
              'preferences_import_unknown',
              '设备恢复结果未知，请先核对设备列表，勿直接重复导入。',
              {
                'preferencesSaved': false,
                'devicesRestored': 'unknown',
                'authorizationRestored': false,
              },
            );
          }
          try {
            await preferences.importSettings(
              imported,
              expectedRevision: expected,
            );
          } catch (error) {
            final unknown =
                error is! PreferenceFailure ||
                error.code == 'preferences_write_unknown';
            throw PreferenceFailure(
              unknown
                  ? 'preferences_import_unknown'
                  : 'preferences_import_partial',
              unknown
                  ? '设备记录已恢复，设置提交结果未知，请重新读取核对，勿重复导入。'
                  : '设备记录已恢复，设置尚未保存，请重新检查设置。',
              {
                'preferencesSaved': unknown ? 'unknown' : false,
                'devicesRestored': restored,
                'authorizationRestored': false,
                'cause': error is PreferenceFailure
                    ? error.code
                    : 'preferences_io',
                if (error is PreferenceFailure && error.details.isNotEmpty)
                  'preferenceFailure': error.details,
              },
            );
          }
          await _publishAndApply(forceBackgroundPolicy: true);
          return restored;
        default:
          throw const PreferenceFailure('unknown_command', '未知设置操作。');
      }
    } on PreferenceFailure catch (error) {
      throw ApplicationCommandException(
        error.code,
        error.message,
        error.details,
      );
    }
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
  Future<void> reconcile() {
    final operation = _tail.then((_) async {
      try {
        await preferences.reload();
        await _publishAndApply(forceBackgroundPolicy: true);
      } on PreferenceFailure catch (error) {
        throw ApplicationCommandException(
          error.code,
          error.message,
          error.details,
        );
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
