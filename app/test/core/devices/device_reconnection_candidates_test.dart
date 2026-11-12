import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/core/devices/models/adb_discovery_endpoint.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

void main() {
  test('候选核验和已取消的解析不取得发现资源，失败重试沿用原发现所有者', () async {
    final discovery = DeviceDiscovery();
    await discovery.close();
    var reads = 0;
    final candidates = DeviceReconnectionCandidates.mdns(() {
      reads++;
      return discovery;
    });
    final endpoint = AdbDiscoveryEndpoint(
      kind: .tlsConnect,
      serviceName: 'phone._adb-tls-connect._tcp.local',
      instance: 'phone',
      hostname: 'phone.local',
      address: '192.0.2.1',
      port: 5555,
      validUntil: DateTime.now().add(const Duration(seconds: 30)),
      generation: 1,
    );
    expect(candidates.isCurrent(endpoint), isFalse);
    final cancelled = AdbCancellation()..cancel();
    await expectLater(
      candidates.resolve('phone', cancellation: cancelled),
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(reads, 0);
    for (var retry = 0; retry < 2; retry++) {
      await expectLater(
        candidates.resolve('phone', cancellation: AdbCancellation()),
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'disposed'),
        ),
      );
      expect(reads, 1);
      expect(candidates.isCurrent(endpoint), isFalse);
    }
  });
}
