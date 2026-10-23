import 'dart:async';
import 'dart:io';

import 'package:device_preferences/device_preferences.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:device_runtime/src/preferences_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

TypeMatcher<InteropException> errorCode(String code) =>
    isA<InteropException>().having((error) => error.code, 'code', code);
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
  late DevicePreferences preferences;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'preferences-runtime-test-',
    );
    preferences = await PreferencesRuntime.prepare(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'saved preference survives an unknown execution receipt and can reconcile',
    () async {
      var fail = true;
      final requests = <Map<String, dynamic>>[];
      final changes = <Map<String, dynamic>>[];
      final runtime = PreferencesRuntime(
        preferences: preferences,
        request: (command, values) async {
          expect(command, 'settings.update');
          requests.add(values);
          if (fail) throw TimeoutException('reply unknown');
          return values;
        },
        onChanged: changes.add,
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
      expect(changes.single['appearance'], 'dark');
      expect(
        (await PreferencesRuntime.prepare(directory))
            .current
            .values['appearance'],
        'dark',
      );
      expect(requests.single.containsKey('appearance'), isFalse);
      fail = false;
      await runtime.reconcile();
      expect(requests, hasLength(2));
      expect(
        runtime.projectSnapshot({
          'settings': {'appearance': 'light'},
        })['settings']['appearance'],
        'dark',
      );
      expect(
        runtime.projectEvent({
          'type': 'settings.changed',
          'sequence': 12,
          'data': <String, dynamic>{},
        })['data']['appearance'],
        'dark',
      );
      await runtime.invoke('settings.update', {'fileViewMode': 'list'});
      expect(runtime.settings['fileViewMode'], 'list');
    },
  );

  test(
    'serialized saves do not publish an old setting after a newer snapshot',
    () async {
      final barrier = Completer<void>();
      var requests = 0;
      final changes = <Map<String, dynamic>>[];
      final runtime = PreferencesRuntime(
        preferences: preferences,
        request: (_, values) async {
          if (requests++ == 0) await barrier.future;
          return values;
        },
        onChanged: changes.add,
      );
      final first = runtime.invoke('settings.update', {'appearance': 'dark'});
      final second = runtime.invoke('settings.update', {
        'appearance': 'system',
      });
      await Future<void>.delayed(Duration.zero);
      barrier.complete();
      await Future.wait([first, second]);
      expect(runtime.settings['appearance'], 'system');
      expect(changes.last['appearance'], 'system');
      expect(await runtime.invoke('settings.get', {}), runtime.settings);
    },
  );

  test('export uses full Dart preferences and leaves native device metadata intact', () async {
    await preferences.update({'appearance': 'dark'});
    final runtime = PreferencesRuntime(
      preferences: preferences,
      request: (_, _) async => metadata({'adbBurstMode': true}),
      onChanged: (_) {},
    );
    final exported = await runtime.invoke('settings.export', {});
    expect(exported['metadata']['settings']['appearance'], 'dark');
    expect(exported['metadata']['devices'].single['name'], 'Phone');
    expect(exported['metadata'].containsKey('privateKeyPem'), isFalse);
  });

  test(
    'unknown device import is not retried and does not activate preferences',
    () async {
      var requests = 0;
      final runtime = PreferencesRuntime(
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
        (await PreferencesRuntime.prepare(directory))
            .current
            .values['appearance'],
        'light',
      );
    },
  );

  test('restore with conflicting local save reports partial success without overwriting', () async {
    final other = await PreferencesRuntime.prepare(directory);
    final runtime = PreferencesRuntime(
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
      (await PreferencesRuntime.prepare(directory))
          .current
          .values['appearance'],
      'system',
    );
  });

  test(
    'restore validates preference data before any device-side command',
    () async {
      var requests = 0;
      final runtime = PreferencesRuntime(
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
      final runtime = PreferencesRuntime(
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
      final restarted = await PreferencesRuntime.prepare(directory);
      final quality = restarted.current.values['deviceQuality'] as Map;
      expect(quality[first]['maxFps'], 30);
      expect(quality[second]['maxSize'], 1920);
    },
  );
}
