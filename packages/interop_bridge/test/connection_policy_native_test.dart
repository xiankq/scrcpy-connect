import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/connection_policy.dart';
import 'package:interop_bridge/src/application_settings.dart';
import 'package:interop_bridge/src/rust/api.dart' as core;
import 'package:interop_bridge/src/native_runtime.dart';
import 'package:interop_bridge/src/rust/frb_generated.dart';

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
          assets['package:interop_bridge/src/rust/frb_generated.io.dart']
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
      await initializeNativeRuntime(
        dataDirectory: directory.path,
        connectionPolicy: policy,
      );
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
      expect(settingsResponse['data'], applicationSettings);
      await expectLater(
        core.initialize(
          dataDirectory: directory.path,
          connectionPolicyJson: jsonEncode(policy.toNativeJson()),
          settingsDefaultsJson: jsonEncode({
            ...applicationSettings,
            'maxFps': 30,
          }),
        ),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('runtime_settings_defaults_mismatch'),
          ),
        ),
      );
      await expectLater(
        initializeNativeRuntime(dataDirectory: directory.path),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('runtime_connection_policy_mismatch'),
          ),
        ),
      );
    },
  );
}
