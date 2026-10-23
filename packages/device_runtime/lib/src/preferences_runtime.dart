import 'dart:async';
import 'dart:io';

import 'package:device_preferences/device_preferences.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:scrcpy_client/scrcpy_client.dart' show defaultVideoQuality;

typedef PreferenceNativeRequest = Future<dynamic> Function(
  String command,
  Map<String, dynamic> parameters,
);

/// Compose this after prepare() and inject initialExecutionSettings into native
/// initialization. The native runtime never reads preferences.json.
final class PreferencesRuntime {
  PreferencesRuntime({
    required this.preferences,
    required this.request,
    required this.onChanged,
  });
  final DevicePreferences preferences;
  final PreferenceNativeRequest request;
  final void Function(Map<String, dynamic> settings) onChanged;
  Future<void> _tail = Future<void>.value();

  static Future<DevicePreferences> prepare(Directory directory) =>
      DevicePreferences.open(
        directory: directory,
        schema: PreferenceSchema(
          defaults: {...preferenceDefaults, ...defaultVideoQuality},
        ),
      );

  Map<String, Object?> get initialExecutionSettings =>
      preferences.schema.executionMirror(preferences.current.toMap());
  Map<String, dynamic> get settings => preferences.current.toMap();
  int get revision => preferences.current.revision;

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

  /// Merge under the same queue as other preference commands so saves for two
  /// devices cannot overwrite each other's quality entry.
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
        throw InteropException(error.code, error.message, error.details);
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
          return await _publishAndApply();
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
          return await _publishAndApply();
        case 'settings.export':
          final exported = Map<String, dynamic>.from(
            await request(command, parameters) as Map,
          );
          final metadata = Map<String, dynamic>.from(
            exported['metadata'] as Map,
          );
          return {
            ...exported,
            'metadata': {...metadata, 'settings': settings},
          };
        case 'settings.import':
          final metadata = parameters['metadata'];
          if (metadata is! Map ||
              metadata['format'] != 'scrcpy-connect-metadata' ||
              metadata['version'] != 1) {
            throw const PreferenceFailure('invalid_data', '设备记录格式或版本不受支持。');
          }
          // Validate all preference data before restoring any device. Imported
          // device preferences are deliberately cleared: Rust assigns fresh IDs.
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
              'metadata': {...metadata, 'settings': <String, Object?>{}},
            });
          } catch (error) {
            if (error is InteropException &&
                const {
                  'invalid_data',
                  'invalid_argument',
                  'invalid_port',
                }.contains(error.code)) {
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
            throw PreferenceFailure(
              'preferences_import_partial',
              '设备记录已恢复，设置尚未保存，请重新检查设置。',
              {
                'preferencesSaved': false,
                'devicesRestored': restored,
                'authorizationRestored': false,
                if (error is PreferenceFailure) 'cause': error.code,
              },
            );
          }
          await _publishAndApply();
          return restored;
        default:
          throw const PreferenceFailure('unknown_command', '未知设置操作。');
      }
    } on PreferenceFailure catch (error) {
      throw InteropException(error.code, error.message, error.details);
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

  Future<Map<String, dynamic>> _publishAndApply() async {
    final saved = settings;
    onChanged(saved);
    try {
      await request('settings.update', initialExecutionSettings);
    } catch (_) {
      throw PreferenceFailure(
        'preferences_apply_unknown',
        '设置已保存，当前设备应用结果尚未确认。',
        {'saved': true, 'applied': 'unknown', 'revision': revision},
      );
    }
    return saved;
  }

  /// Reapply a durable snapshot after reattachment or an uncertain receipt.
  /// This never retries device restoration or rewrites a preference revision.
  Future<void> reconcile() {
    final operation = _tail.then((_) async {
      try {
        await preferences.reload();
        await _publishAndApply();
      } on PreferenceFailure catch (error) {
        throw InteropException(error.code, error.message, error.details);
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
