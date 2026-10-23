import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'package:flutter_test/flutter_test.dart';
import 'package:device_connections/device_connections.dart';
import 'package:device_protocol/device_protocol.dart' show InteropException;
import 'package:device_runtime/src/rust/api.dart' as core;
import 'package:device_runtime/src/native_runtime.dart';
import 'package:device_runtime/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dart policy initializes native executor and rejects later policy drift',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'connection-policy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      // Flutter test bundles hook assets outside the application loader paths.
      final manifest = jsonDecode(
        await rootBundle.loadString('NativeAssetsManifest.json'),
      ) as Map<String, dynamic>;
      final nativeAssets = manifest['native-assets'] as Map<String, dynamic>;
      final assets = nativeAssets.values.single as Map<String, dynamic>;
      final location =
          assets['package:device_runtime/src/rust/frb_generated.io.dart']
              as List<Object?>;
      expect(location.first, 'absolute');
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(location[1] as String),
      );
      const policy = ConnectionPolicy(
        requestAuthorization: false,
        connectTimeout: Duration(seconds: 7),
        healthEnabled: false,
        reconnectEnabled: false,
        tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
      );
      var repository = Directory.current;
      while (!File('${repository.path}/Cargo.toml').existsSync()) {
        final parent = repository.parent;
        if (parent.path == repository.path) {
          throw StateError('Repository not found');
        }
        repository = parent;
      }
      final adbDirectory = Directory(
        '${repository.path}/.dart_tool/flutter_adb/'
        '${Platform.isMacOS ? 'macos' : Platform.operatingSystem}',
      );
      await initializeNativeRuntime(
        dataDirectory: directory.path,
        connectionPolicy: policy,
        adbBinaryDirectory: adbDirectory,
      );
      addTearDown(shutdownNativeAdb);
      await initializeNativeRuntime(
        dataDirectory: directory.path,
        connectionPolicy: policy,
      );
      final settingsResponse = jsonDecode(
        await core.invoke(
          requestJson: jsonEncode({
            'command': 'settings.get',
            'params': <String, Object?>{},
          }),
        ),
      ) as Map<String, dynamic>;
      expect(settingsResponse['ok'], isTrue);
      expect(
        settingsResponse['data'],
        nativePreferences.schema.executionMirror(
          nativePreferences.current.toMap(),
        ),
      );
      await nativePreferences.update({'maxFps': 30, 'appearance': 'dark'});
      await initializeNativeRuntime(
        dataDirectory: directory.path,
        connectionPolicy: policy,
      );
      final reapplied = jsonDecode(
        await core.invoke(
          requestJson: jsonEncode({
            'command': 'settings.get',
            'params': <String, Object?>{},
          }),
        ),
      ) as Map<String, dynamic>;
      expect(reapplied['data']['maxFps'], 30);
      expect((reapplied['data'] as Map).containsKey('appearance'), isFalse);
      await expectLater(
        initializeNativeRuntime(dataDirectory: directory.path),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            'runtime_connection_policy_mismatch',
          ),
        ),
      );
    },
  );
}
