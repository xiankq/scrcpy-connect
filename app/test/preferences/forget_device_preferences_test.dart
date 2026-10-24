import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/preferences/preference_commands.dart';
import 'package:scrcpy_connect/preferences/preference_store.dart';

const _forgotten = '7b2a4273-cd2e-4aca-b86e-1e6d81170c81';
const _remaining = '8cd3c688-670c-46c1-b605-d140d9d8b4aa';

void main() {
  late Directory directory;
  late PreferenceStore preferences;
  final changes = <Map<String, dynamic>>[];

  PreferenceCommands commands({bool failApply = false}) => PreferenceCommands(
    preferences: preferences,
    request: (_, _) async => fail('清理偏好不重放设备遗忘或建立原生镜像'),
    onChanged: (values) {
      changes.add(values);
      if (failApply) throw StateError('应用通知失败');
    },
  );

  setUp(() async {
    changes.clear();
    directory = await Directory.systemTemp.createTemp('forgotten-preferences-');
    preferences = await PreferenceCommands.prepare(directory);
    await preferences.update({
      'appearance': 'dark',
      'deviceQuality': {
        _forgotten: {'maxFps': 30},
        _remaining: {'maxFps': 60},
      },
      'deviceSettings': {
        _forgotten: {'stayAwake': true, 'clipboardSync': true},
        _remaining: {'stayAwake': false, 'clipboardSync': false},
      },
    });
  });
  tearDown(() => directory.delete(recursive: true));

  test('遗忘持久清理两类设备偏好并保留其他设备与全局偏好', () async {
    await commands().forgetDevicePreferences(_forgotten);
    final reopened = await PreferenceCommands.prepare(directory);
    expect(reopened.current.values['deviceQuality'], {
      _remaining: {'maxFps': 60},
    });
    expect(reopened.current.values['deviceSettings'], {
      _remaining: {'stayAwake': false, 'clipboardSync': false},
    });
    expect(reopened.current.values['appearance'], 'dark');
    expect(changes.single['deviceQuality'], isNot(contains(_forgotten)));
    expect(changes.single['deviceSettings'], isNot(contains(_forgotten)));
  });

  test('保存冲突保留其他所有者的修改并允许只重试偏好清理', () async {
    final other = await PreferenceCommands.prepare(directory);
    await other.update({'appearance': 'system'});
    final runtime = commands();
    await expectLater(
      runtime.forgetDevicePreferences(_forgotten),
      throwsA(
        isA<ApplicationCommandException>()
            .having(
              (error) => error.code,
              'code',
              'preferences_cleanup_partial',
            )
            .having(
              (error) => error.details,
              'details',
              allOf(
                containsPair('deviceForgotten', true),
                containsPair('preferencesSaved', false),
                containsPair('cause', 'preferences_conflict'),
              ),
            ),
      ),
    );
    expect(changes, isEmpty);
    final beforeRetry = await PreferenceCommands.prepare(directory);
    expect(beforeRetry.current.values['deviceQuality'], contains(_forgotten));
    await runtime.forgetDevicePreferences(_forgotten);
    final reopened = await PreferenceCommands.prepare(directory);
    expect(reopened.current.values['appearance'], 'system');
    expect(
      reopened.current.values['deviceQuality'],
      isNot(contains(_forgotten)),
    );
    expect(reopened.current.values['deviceQuality'], contains(_remaining));
  });

  test('持久文件读取失败保留未知语义且修复存储后可重试清理', () async {
    final file = File.fromUri(directory.uri.resolve('preferences.json'));
    final original = await file.readAsBytes();
    await file.delete();
    final unavailable = await Directory(file.path).create();
    final runtime = commands();
    await expectLater(
      runtime.forgetDevicePreferences(_forgotten),
      throwsA(
        isA<ApplicationCommandException>()
            .having(
              (error) => error.code,
              'code',
              'preferences_cleanup_unknown',
            )
            .having(
              (error) => error.details,
              'details',
              allOf(
                containsPair('deviceForgotten', true),
                containsPair('preferencesSaved', 'unknown'),
              ),
            ),
      ),
    );
    expect(changes, isEmpty);
    expect(preferences.current.values['deviceQuality'], contains(_forgotten));
    await unavailable.delete();
    await file.writeAsBytes(original, flush: true);
    await runtime.forgetDevicePreferences(_forgotten);
    expect(
      (await PreferenceCommands.prepare(directory))
          .current
          .values['deviceQuality'],
      isNot(contains(_forgotten)),
    );
  });

  test('应用通知失败仍已持久清理且重新附着不复活孤儿偏好', () async {
    final runtime = commands(failApply: true);
    await expectLater(
      runtime.forgetDevicePreferences(_forgotten),
      throwsA(
        isA<ApplicationCommandException>()
            .having((error) => error.code, 'code', 'preferences_apply_unknown')
            .having(
              (error) => error.details,
              'details',
              allOf(
                containsPair('deviceForgotten', true),
                containsPair('preferencesSaved', true),
                containsPair('applied', 'unknown'),
              ),
            ),
      ),
    );
    preferences = await PreferenceCommands.prepare(directory);
    expect(
      preferences.current.values['deviceQuality'],
      isNot(contains(_forgotten)),
    );
    expect(
      preferences.current.values['deviceSettings'],
      isNot(contains(_forgotten)),
    );
    await commands().reconcile();
    expect(changes.last['deviceQuality'], isNot(contains(_forgotten)));
    expect(changes.last['deviceSettings'], isNot(contains(_forgotten)));
    expect(changes.last['deviceQuality'], contains(_remaining));
  });

  test('画质保存与遗忘共用队列且重复清理不增加持久版本', () async {
    final runtime = commands();
    final saved = runtime.saveDeviceQuality(_remaining, {'maxFps': 45});
    final forgotten = runtime.forgetDevicePreferences(_forgotten);
    await Future.wait([saved, forgotten]);
    final revision = preferences.current.revision;
    await runtime.forgetDevicePreferences(_forgotten);
    expect(preferences.current.revision, revision);
    final reopened = await PreferenceCommands.prepare(directory);
    expect(reopened.current.values['deviceQuality'], {
      _remaining: {'maxFps': 45},
    });
  });
}
