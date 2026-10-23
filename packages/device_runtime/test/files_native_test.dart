import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_runtime/device_runtime.dart';
import 'package:device_runtime/src/native_runtime.dart';
import 'package:device_runtime/src/rust/frb_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> settled(
  DeviceRuntime runtime,
  String id, {
  String? status,
}) async {
  return Future<Map<String, dynamic>>(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final task = await runtime.request('transfers.get', {'transferId': id});
      if (status != null
          ? task['status'] == status
          : ![
              'queued',
              'running',
              'finalizing',
              'cancelling',
            ].contains(task['status'])) {
        return task;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('File task did not settle');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Platform.environment['INTEROP_FILES_AVD'];
  test(
    'actual assembled runtime browses searches copies conflicts cancels and reopens journal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'assembled-files-',
      );
      var repository = Directory.current;
      while (!File('${repository.path}/Cargo.toml').existsSync()) {
        if (repository.parent.path == repository.path) {
          throw StateError('Repository not found');
        }
        repository = repository.parent;
      }
      final key =
          Platform.environment['INTEROP_ADB_KEY'] ??
          '${Platform.environment['HOME']}/.android/adbkey';
      await File(key).copy('${directory.path}/host_identity.pem');
      final manifest = jsonDecode(
        await rootBundle.loadString('NativeAssetsManifest.json'),
      ) as Map<String, dynamic>;
      final assets = (manifest['native-assets'] as Map).values.single as Map;
      final location =
          assets['package:device_runtime/src/rust/frb_generated.io.dart']
              as List;
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(location[1] as String),
      );
      const policy = ConnectionPolicy(
        requestAuthorization: true,
        healthEnabled: false,
        reconnectEnabled: false,
      );
      await initializeNativeRuntime(
        dataDirectory: directory.path,
        connectionPolicy: policy,
        adbBinaryDirectory: Directory(
          '${repository.path}/.dart_tool/flutter_adb/${Platform.operatingSystem}',
        ),
      );
      DeviceRuntime? runtime;
      String? device;
      final remote =
          '/data/local/tmp/assembled-files-${DateTime.now().microsecondsSinceEpoch}';
      try {
        runtime = await DeviceRuntime.initialize(
          dataDirectory: directory.path,
          connectionPolicy: policy,
        );
        final address = endpoint!.split(':');
        device =
            (await runtime.request('devices.add', {
                  'address': address[0],
                  'port': int.parse(address[1]),
                }))['deviceId']
                as String;
        await runtime.request('devices.connect', {'deviceId': device});
        await runtime.request('files.mkdir', {
          'deviceId': device,
          'path': remote,
        });
        final bytes = List<int>.generate(4096, (i) => i % 251);
        final source = File('${directory.path}/source.bin');
        await source.writeAsBytes(bytes, flush: true);
        final pushed = await runtime.request('files.push', {
          'deviceId': device,
          'source': source.path,
          'destination': '$remote/source.bin',
        });
        expect(
          (await settled(runtime, pushed['transferId'] as String))['status'],
          'completed',
        );
        final listed = await runtime.request('files.list', {
          'deviceId': device,
          'path': remote,
        });
        expect((listed['entries'] as List).single['size'], 4096);
        final search = await runtime.request('files.search.start', {
          'deviceId': device,
          'path': remote,
          'query': 'source',
        });
        Map<String, dynamic> found;
        do {
          found = await runtime.request('files.search.get', {
            'deviceId': device,
            'searchId': search['searchId'],
          });
          if (found['status'] == 'running') {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } while (found['status'] == 'running');
        expect((found['entries'] as List).single['path'], '$remote/source.bin');
        final destination = File('${directory.path}/download.bin');
        final pulled = await runtime.request('files.pull', {
          'deviceId': device,
          'path': '$remote/source.bin',
          'destination': destination.path,
        });
        expect(
          (await settled(runtime, pulled['transferId'] as String))['status'],
          'completed',
        );
        expect(
          await destination.readAsBytes(),
          bytes,
          reason: 'exact binary equality is stronger than a matching hash',
        );
        final conflict = await runtime.request('files.push', {
          'deviceId': device,
          'source': source.path,
          'destination': '$remote/source.bin',
        });
        final conflictId = conflict['transferId'] as String;
        expect(
          (await settled(runtime, conflictId, status: 'conflict'))['status'],
          'conflict',
        );
        final snapshot = await runtime.request('state.snapshot');
        expect(
          (snapshot['transfers'] as List).any(
            (dynamic t) => t['id'] == conflictId,
          ),
          isTrue,
        );
        expect(
          (snapshot['activities'] as List).any(
            (dynamic a) => a['id'] == 'transfer:$conflictId',
          ),
          isTrue,
        );
        await runtime.request('activities.stop', {
          'activityId': 'transfer:$conflictId',
        });
        expect((await settled(runtime, conflictId))['status'], 'cancelled');
        await runtime.dispose();
        runtime = await DeviceRuntime.initialize(
          dataDirectory: directory.path,
          connectionPolicy: policy,
        );
        expect(
          (await runtime.request('transfers.get', {
            'transferId': pulled['transferId'],
          }))['status'],
          'completed',
        );
        expect(
          (await runtime.request('transfers.get', {
            'transferId': conflictId,
          }))['status'],
          'cancelled',
        );
        await runtime.request('transfers.remove', {
          'batchId': pulled['batchId'],
        });
        expect(
          await destination.readAsBytes(),
          bytes,
          reason: 'history removal must never delete the downloaded file',
        );
      } finally {
        if (runtime != null) {
          if (device != null) {
            try {
              await runtime.request('files.delete', {
                'deviceId': device,
                'paths': [remote],
              });
            } catch (_) {
              /* unique fixture only */
            }
            try {
              await runtime.request('devices.disconnect', {'deviceId': device});
            } catch (_) {
              /* shutdown still owns cleanup */
            }
          }
          await runtime.shutdown();
        } else {
          await shutdownNativeAdb();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: endpoint == null
        ? 'requires explicit authorized INTEROP_FILES_AVD endpoint'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
