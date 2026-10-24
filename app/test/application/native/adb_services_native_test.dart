import 'package:scrcpy/scrcpy.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Platform.environment['INTEROP_ADB_SERVICES_AVD'];
  test(
    'full adb typed services use owned official transport and release resources',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'typed-adb-services-',
      );
      var repo = Directory.current;
      while (!File('${repo.path}/Cargo.toml').existsSync()) {
        if (repo.parent.path == repo.path) {
          throw StateError('Repository not found');
        }
        repo = repo.parent;
      }
      final key =
          Platform.environment['INTEROP_ADB_KEY'] ??
          '${Platform.environment['HOME']}/.android/adbkey';
      await File(key).copy('${directory.path}/host_identity.pem');
      final bindings = await createNativeScrcpyAdbApi();
      AdbHost? host;
      AdbDevice? device;
      final remote =
          '/data/local/tmp/typed-adb-${DateTime.now().microsecondsSinceEpoch}';
      try {
        host = await AdbHost.prepare(
          bindings: bindings,
          dataDirectory: directory,
          binaryDirectory: Directory(
            '${repo.path}/.dart_tool/adb/${Platform.operatingSystem}',
          ),
        );
        final client = host.client;
        device = await client.connect(endpoint!);
        final facts = await client.services.connectionFacts(device);
        expect(facts.officialServer, isTrue);
        expect(facts.transportId, greaterThan(0));
        expect(facts.protocolVersion, isNull);
        expect(
          (await client.devices())
              .where((d) => d.serial == device!.serial)
              .single
              .id,
          device.id,
        );
        final shell = await client.services.shell(
          device,
          'cat; printf error >&2; exit 7',
        );
        final output = shell.events.toList();
        final bytes = List<int>.generate(4096, (i) => i % 256);
        await shell.addStream(Stream.value(bytes));
        await shell.closeStdin();
        final events = await output;
        expect(
          events.where((e) => e.kind == 'stdout').expand((e) => e.bytes),
          bytes,
        );
        expect(
          events.where((e) => e.kind == 'stderr').expand((e) => e.bytes),
          utf8.encode('error'),
        );
        expect(events.last.exitCode, 7);
        final exec = await client.services.exec(device, 'printf raw');
        expect(
          (await exec.events.toList()).expand((e) => e.bytes),
          utf8.encode('raw'),
        );
        final sync = client.services.sync(device);
        final path = AdbPath(remote);
        expect(await sync.push(path, Stream.value(bytes)), bytes.length);
        expect((await sync.stat(path)).size, bytes.length);
        expect((await sync.lstat(path)).isFile, isTrue);
        expect(
          (await sync.list(AdbPath('/data/local/tmp')).toList()).any(
            (e) =>
                utf8.decode(e.name, allowMalformed: true) ==
                remote.split('/').last,
          ),
          isTrue,
        );
        expect(
          (await sync.pull(path).toList()).expand((chunk) => chunk),
          bytes,
        );
        for (final compression in AdbCompression.values.where(
          (mode) => mode != AdbCompression.none,
        )) {
          final feature = switch (compression) {
            AdbCompression.brotli => 'sendrecv_v2_brotli',
            AdbCompression.lz4 => 'sendrecv_v2_lz4',
            AdbCompression.zstd => 'sendrecv_v2_zstd',
            AdbCompression.none => '',
          };
          if (!device.features.contains(feature)) continue;
          expect(
            await sync.push(
              path,
              Stream.value(bytes),
              compression: compression,
            ),
            bytes.length,
          );
          expect(
            (await sync.pull(path, compression: compression).toList()).expand(
              (chunk) => chunk,
            ),
            bytes,
          );
        }
        expect(
          await client.services.jdwp(device),
          everyElement(greaterThan(0)),
        );
        final listener = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        try {
          final binding = await client.services.reverse(
            device,
            AdbReverseSocket.tcp(0),
            InternetAddress.loopbackIPv4,
            listener.port,
          );
          expect(
            (await client.services.reverseList(device))
                .any((m) => m.deviceService == binding.service),
            isTrue,
          );
          await client.services.reverseRemove(device, binding);
          expect(
            (await client.services.reverseList(device))
                .any((m) => m.deviceService == binding.service),
            isFalse,
          );
        } finally {
          await listener.close();
        }
        final token = AdbCancellation();
        final waiting = await client.services.open(
          device,
          'shell:sleep 30',
          cancellation: token,
        );
        final pending = waiting.events.toList();
        final cancelled = expectLater(pending, throwsA(anything));
        token.cancel();
        await cancelled;
        expect((await client.services.connectionFacts(device)).closed, isFalse);
        await expectLater(
          sync.push(AdbPath('/proc/typed-adb-denied'), Stream.value(bytes)),
          throwsA(anything),
        );
        final local = File('${directory.path}/pulled');
        expect(await sync.pullFile(path, local), bytes.length);
        expect(await local.readAsBytes(), bytes);
        await expectLater(sync.pullFile(path, local), throwsA(anything));
        expect(await local.readAsBytes(), bytes);
      } finally {
        if (host != null && device != null) {
          await host.client.shell(device, 'rm -f $remote').drain<void>();
          await host.client.disconnect(device);
        }
        final port = host?.nativeConfiguration?['port'] as int?;
        await host?.close();
        if (port != null) {
          await expectLater(
            Socket.connect('127.0.0.1', port),
            throwsA(isA<SocketException>()),
          );
        }
        await directory.delete(recursive: true);
      }
    },
    skip: endpoint == null
        ? 'Set INTEROP_ADB_SERVICES_AVD to an explicitly authorized test AVD'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
