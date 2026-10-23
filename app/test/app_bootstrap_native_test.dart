import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:device_runtime/device_runtime.dart';
import 'package:device_runtime/src/native_runtime.dart';
import 'package:device_runtime/src/rust/frb_generated.dart' show RustLib;
import 'package:scrcpy_connect/services/app_bootstrap.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real bridge can retry bootstrap after outgoing preparation fails', () async {
    // Flutter tests bundle hook assets outside FRB's application loader paths.
    // Preload that real adapter; product bootstrap still owns its attachment.
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
    final root = await Directory.systemTemp.createTemp('connect-bootstrap-');
    final cache = await Directory.systemTemp.createTemp(
      'connect-bootstrap-cache-',
    );
    var repository = Directory.current;
    while (!File('${repository.path}/Cargo.toml').existsSync()) {
      final parent = repository.parent;
      if (parent.path == repository.path) {
        throw StateError('Repository not found');
      }
      repository = parent;
    }
    await initializeNativeRuntime(
      dataDirectory: root.path,
      adbBinaryDirectory: Directory(
        '${repository.path}/.dart_tool/flutter_adb/'
        '${Platform.isMacOS ? 'macos' : Platform.operatingSystem}',
      ),
    );
    AppDependencies? owner;
    final bridges = <DeviceRuntime>[];
    Future<AppDependencies> open() async {
      final pending = DeviceRuntime.initialize(dataDirectory: root.path);
      if (bridges.isEmpty) {
        await expectLater(
          DeviceRuntime.initialize(dataDirectory: '${root.path}/different'),
          throwsA(
            isA<InteropException>().having(
              (error) => error.code,
              'code',
              'runtime_directory_mismatch',
            ),
          ),
        );
      }
      final bridge = await pending;
      bridges.add(bridge);
      return AppDependencies(
        request: bridge.request,
        events: bridge.events,
        close: bridge.dispose,
        initialize: false,
      );
    }

    try {
      final failure = FileSystemException('temporary storage unavailable');
      await expectLater(
        bootstrapApplication(
          initializeTransport: open,
          prepareOutgoingDirectory: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
      await expectLater(
        bridges.single.request('settings.get'),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            'disposed',
          ),
        ),
      );

      final outgoing = await Directory('${cache.path}/outgoing').create();
      owner = await bootstrapApplication(
        initializeTransport: open,
        prepareOutgoingDirectory: () async => outgoing,
      );
      expect(bridges, hasLength(2));
      expect(await owner.request('settings.get'), isA<Json>());
      final status = await owner.request('media.cache.status');
      expect(status, isNotEmpty);
    } finally {
      await owner?.close?.call();
      // Every bridge dispose is idempotent, including the failed owner.
      for (final bridge in bridges) {
        await bridge.dispose();
      }
      if (bridges.isNotEmpty) {
        await bridges.last.shutdown();
      } else {
        await shutdownNativeAdb();
      }
      await root.delete(recursive: true);
      await cache.delete(recursive: true);
    }
  });
}
