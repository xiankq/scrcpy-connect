import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_connect/stores/preference_store.dart';
import 'package:scrcpy_connect/models/preference_schema.dart';
import 'package:flutter_test/flutter_test.dart';

const firstId = '7b2a4273-cd2e-4aca-b86e-1e6d81170c81';
const secondId = '8cd3c688-670c-46c1-b605-d140d9d8b4aa';
final schema = PreferenceSchema(
  defaults: const {
    'qualityPreset': 'balanced',
    'maxSize': 1280,
    'maxFps': 60,
    'videoBitRate': 4000000,
    'videoCodec': 'h264',
    'videoEncoder': null,
  },
);
Matcher failure(String code) =>
    isA<PreferenceFailure>().having((error) => error.code, 'code', code);

void main() {
  late Directory directory;
  File file(String name) => File.fromUri(directory.uri.resolve(name));
  Future<PreferenceStore> open() =>
      PreferenceStore.open(directory: directory, schema: schema);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'device-preferences-test-',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'device records without a preference owner keep their original bytes',
    () async {
      final original = jsonEncode({
        'version': 2,
        'devices': [
          {'id': firstId, 'name': 'Phone'},
        ],
        'identityFingerprint': 'existing-identity',
      });
      await file('devices.json').writeAsString(original);
      final preferences = await open();
      expect(preferences.current.toMap(), schema.defaults);
      expect(await file('devices.json').readAsString(), original);
    },
  );

  test('v1 migration preserves device and authorization bytes and explicit overrides', () async {
    final legacy = jsonEncode({
      'version': 1,
      'identityFingerprint': 'existing-identity',
      'deviceIdentityFingerprints': {firstId: 'device-identity'},
      'devices': [
        {'id': firstId, 'name': 'Phone'},
      ],
      'settings': {
        'appearance': 'dark',
        'adbBurstMode': false,
        'qualityPreset': 'balanced',
        'maxSize': 1280,
        'maxFps': 60,
        'videoBitRate': 8000000,
        'audioMode': 'fixed',
        'clipboardSync': true,
        'deviceQuality': {
          firstId: {
            'qualityPreset': 'balanced',
            'maxSize': 1280,
            'maxFps': 60,
            'videoBitRate': 8000000,
          },
          secondId: {
            'qualityPreset': 'balanced',
            'maxSize': 1280,
            'maxFps': 30,
            'videoBitRate': 8000000,
          },
        },
        'deviceSettings': {
          firstId: {'clipboardSync': false, 'showNavigationBar': false},
        },
      },
    });
    await file('devices.json').writeAsString(legacy);
    await file('host_identity.pem').writeAsString('existing private identity');
    final preferences = await open();
    expect(preferences.current.values['appearance'], 'dark');
    expect(preferences.current.values['videoBitRate'], 4000000);
    expect(preferences.current.values['adbBurstMode'], isTrue);
    expect(
      (preferences.current.values['deviceQuality']
          as Map)[secondId]['videoBitRate'],
      8000000,
    );
    expect(preferences.current.values.containsKey('audioMode'), isFalse);
    expect(preferences.current.values.containsKey('clipboardSync'), isFalse);
    expect(
      (preferences.current.values['deviceSettings']
          as Map)[firstId]['clipboardSync'],
      isFalse,
    );
    expect(await file('devices.json').readAsString(), legacy);
    expect(
      await file('host_identity.pem').readAsString(),
      'existing private identity',
    );
    await file('devices.json').writeAsString('legacy no longer valid');
    expect((await open()).current.values['appearance'], 'dark');
  });

  test(
    'v2 explicit former bitrate and burst values survive migration',
    () async {
      await file('devices.json').writeAsString(
        jsonEncode({
          'version': 2,
          'settings': {
            'qualityPreset': 'balanced',
            'maxSize': 1280,
            'maxFps': 60,
            'videoBitRate': 8000000,
            'adbBurstMode': false,
          },
        }),
      );
      final preferences = await open();
      expect(preferences.current.values['videoBitRate'], 8000000);
      expect(preferences.current.values['adbBurstMode'], isFalse);
    },
  );

  test(
    'serialized updates preserve both choices, stale owners report conflict',
    () async {
      final first = await open(), stale = await open();
      await Future.wait([
        first.update({'appearance': 'dark'}),
        first.update({'fileViewMode': 'list'}),
      ]);
      expect(first.current.values['appearance'], 'dark');
      expect(first.current.values['fileViewMode'], 'list');
      await expectLater(
        stale.update({'fileSortKey': 'size'}),
        throwsA(failure('preferences_conflict')),
      );
      expect(stale.current.revision, first.current.revision);
      await stale.update({'fileSortKey': 'size'});
      final restarted = await open();
      expect(restarted.current.values['appearance'], 'dark');
      expect(restarted.current.values['fileSortKey'], 'size');
    },
  );

  test(
    'bad new and old files are preserved and never replaced with defaults',
    () async {
      await file('devices.json').writeAsString('corrupt old bytes');
      await expectLater(open(), throwsA(failure('preferences_corrupt')));
      expect(await file('devices.json').readAsString(), 'corrupt old bytes');
      expect(await file('preferences.json').exists(), isFalse);
      await file('devices.json').delete();
      await open();
      await file('preferences.json').writeAsString('{truncated');
      await expectLater(open(), throwsA(failure('preferences_corrupt')));
      expect(await file('preferences.json').readAsString(), '{truncated');
    },
  );

  test(
    'invalid updates leave committed bytes unchanged, reset survives restart',
    () async {
      final preferences = await open();
      await preferences.update({'appearance': 'dark', 'fileViewMode': 'list'});
      final before = await file('preferences.json').readAsBytes();
      for (final update in [
        {'maxFps': 0},
        {'privateKeyPem': 'secret'},
        {
          'deviceSettings': {
            firstId: {'remoteCustomRatio': 'NaN:1'},
          },
        },
      ]) {
        expect(
          () => preferences.update(update),
          throwsA(failure('invalid_argument')),
        );
      }
      expect(await file('preferences.json').readAsBytes(), before);
      await preferences.reset(keys: {'appearance'});
      final restarted = await open();
      expect(restarted.current.values['appearance'], 'light');
      expect(restarted.current.values['fileViewMode'], 'list');
      await restarted.reset();
      expect((await open()).current.values, schema.defaults);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.endsWith('.tmp'))
            .length,
        0,
      );
    },
  );

  test('metadata imports global choices while preserving local device preferences and ignoring file bindings', () async {
    final preferences = await open();
    await preferences.update({
      'deviceSettings': {
        firstId: {'stayAwake': false},
      },
      'deviceQuality': {
        firstId: {'maxFps': 60},
      },
      'appOpenModes': {
        firstId: {'com.example.phone': 'phone'},
      },
    });
    await preferences.importSettings({
      'appearance': 'dark',
      'audioMode': 'fixed',
      'deviceSettings': {
        firstId: {'stayAwake': true, 'clipboardSync': true},
      },
      'deviceQuality': {
        firstId: {'maxFps': 30},
      },
    });
    expect(preferences.current.values['appearance'], 'dark');
    expect(preferences.current.values['deviceSettings'], {
      firstId: {'stayAwake': false},
    });
    expect(preferences.current.values['deviceQuality'], {
      firstId: {'maxFps': 60},
    });
    expect(preferences.current.values['appOpenModes'], {
      firstId: {'com.example.phone': 'phone'},
    });
    expect(await file('host_identity.pem').exists(), isFalse);
    expect(await file('devices.json').exists(), isFalse);
  });
}
