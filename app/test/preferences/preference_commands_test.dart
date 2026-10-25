import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/preferences/preference_store.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/preferences/preference_commands.dart';
import 'package:flutter_test/flutter_test.dart';

TypeMatcher<ApplicationCommandException> errorCode(String code) =>
    isA<ApplicationCommandException>().having(
      (error) => error.code,
      'code',
      code,
    );
Map<String, dynamic> metadata([
  Map<String, Object?> settings = const {'appearance': 'dark'},
]) => {
  'metadata': {
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
  },
};

void main() {
  late Directory directory;
  late PreferenceStore preferences;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'preferences-runtime-test-',
    );
    preferences = await PreferenceCommands.prepare(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('命名读取等待正在保存和应用的偏好，不绕过原有串行队列', () async {
    final applying = Completer<void>();
    final release = Completer<void>();
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (_, _) async => fail('读取偏好不得调用设备分派器'),
      onChanged: (_) {},
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
    var returned = false;
    final reading = runtime.read().then((settings) {
      returned = true;
      return settings;
    });
    await Future<void>.delayed(Duration.zero);
    expect(returned, isFalse);
    release.complete();
    await saving;
    expect((await reading)['appearance'], 'dark');
    expect(returned, isTrue);
  });

  test('重置后台偏好立即恢复执行策略且不重复应用无关设置', () async {
    await preferences.update({'backgroundKeepAlive': false});
    final applied = <bool>[];
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (_, values) async => values,
      onChanged: (_) {},
      applyBackgroundPolicy: (enabled) async => applied.add(enabled),
    );

    await runtime.invoke('settings.reset', {
      'keys': ['backgroundKeepAlive'],
    });
    expect(runtime.settings['backgroundKeepAlive'], isTrue);
    expect(applied, [true]);
    await runtime.invoke('settings.update', {'appearance': 'dark'});
    expect(applied, [true]);
  });

  test('偏好保存不创建原生镜像，后台回执未知可核验而不改写版本', () async {
    var rejected = true;
    final applied = <bool>[];
    final changes = <Map<String, dynamic>>[];
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (_, _) async => fail('保存偏好不得调用设备或原生业务'),
      onChanged: changes.add,
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
  });

  test('串行保存等待实际后台应用，后继快照不被旧通知覆盖', () async {
    final started = Completer<void>(), barrier = Completer<void>();
    final changes = <Map<String, dynamic>>[];
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (_, _) async => fail('保存偏好不得调用设备或原生业务'),
      applyBackgroundPolicy: (_) async {
        started.complete();
        await barrier.future;
      },
      onChanged: changes.add,
    );
    final first = runtime.invoke('settings.update', {
      'appearance': 'dark',
      'backgroundKeepAlive': false,
    });
    await started.future;
    final second = runtime.invoke('settings.update', {'appearance': 'system'});
    await Future<void>.delayed(Duration.zero);
    expect(changes, hasLength(1));
    barrier.complete();
    await Future.wait([first, second]);
    expect(changes.map((value) => value['appearance']), ['dark', 'system']);
    expect(runtime.settings['appearance'], 'system');
  });

  test('保存后的应用通知异常明确保留持久结果，重新核验只发布当前快照', () async {
    var rejected = true;
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (_, _) async => fail('重新核验不重放设备命令'),
      onChanged: (_) {
        if (rejected) throw StateError('观察者失败');
      },
    );
    await expectLater(
      runtime.invoke('settings.update', {'appearance': 'dark'}),
      throwsA(
        errorCode('preferences_apply_unknown').having(
          (error) => error.details,
          'details',
          containsPair('saved', true),
        ),
      ),
    );
    expect(preferences.current.values['appearance'], 'dark');
    rejected = false;
    await runtime.reconcile();
    expect(runtime.settings['appearance'], 'dark');
  });

  test('导出由 Dart 组装兼容 v1 元数据且只读取设备事实', () async {
    await preferences.update({'appearance': 'dark'});
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (command, parameters) async {
        expect(command, 'devices.list');
        expect(parameters, isEmpty);
        return {
          'devices': [
            {
              'id': '内部记录标识',
              'name': 'Phone',
              'address': 'phone.local',
              'port': 5555,
              'transport': 'tcp',
              'guid': null,
              'serial': '真实序列号',
              'model': '型号',
              'androidVersion': '16',
              'apiLevel': 36,
              'autoReconnect': true,
              'connectionId': '临时连接句柄',
              'privateKeyPem': '禁止导出的私钥',
              'identityFingerprint': '内部身份指纹',
            },
          ],
        };
      },
      onChanged: (_) {},
    );
    final exported = await runtime.invoke('settings.export', {});
    expect(exported['metadata']['settings']['appearance'], 'dark');
    expect(exported['metadata']['format'], 'scrcpy-connect-metadata');
    expect(exported['metadata']['version'], 1);
    expect(exported['metadata']['devices'], [
      {
        'name': 'Phone',
        'address': 'phone.local',
        'port': 5555,
        'transport': 'tcp',
        'guid': null,
        'serial': '真实序列号',
        'model': '型号',
        'androidVersion': '16',
        'apiLevel': 36,
      },
    ]);
  });

  test('导出保留设备读取失败且拒绝将畸形结果伪装成空备份', () async {
    var malformed = false;
    final runtime = PreferenceCommands(
      preferences: preferences,
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

  test(
    'unknown device import is not retried and does not activate preferences',
    () async {
      var requests = 0;
      final runtime = PreferenceCommands(
        preferences: preferences,
        request: (_, _) async {
          requests++;
          throw TimeoutException('unknown');
        },
        onChanged: (_) {},
      );
      await expectLater(
        runtime.invoke('settings.import', metadata()),
        throwsA(errorCode('preferences_import_unknown')),
      );
      expect(requests, 1);
      expect(preferences.current.values['appearance'], 'light');
      expect(
        (await PreferenceCommands.prepare(directory))
            .current
            .values['appearance'],
        'light',
      );
    },
  );

  test('restore with conflicting local save reports partial success without overwriting', () async {
    final other = await PreferenceCommands.prepare(directory);
    final runtime = PreferenceCommands(
      preferences: preferences,
      request: (command, values) async {
        expect(command, 'settings.import');
        expect((values['metadata'] as Map)['settings'], isEmpty);
        await other.update({'appearance': 'system'});
        return {'restored': 1, 'authorizationRestored': false};
      },
      onChanged: (_) {},
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

  test(
    'restore validates preference data before any device-side command',
    () async {
      var requests = 0;
      final runtime = PreferenceCommands(
        preferences: preferences,
        request: (_, _) async {
          requests++;
          return {};
        },
        onChanged: (_) {},
      );
      await expectLater(
        runtime.invoke(
          'settings.import',
          metadata({'privateKeyPem': 'secret'}),
        ),
        throwsA(errorCode('invalid_argument')),
      );
      expect(requests, 0);
    },
  );
  test(
    'concurrent quality saves retain both device choices after restart',
    () async {
      final runtime = PreferenceCommands(
        preferences: preferences,
        request: (_, values) async => values,
        onChanged: (_) {},
      );
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
