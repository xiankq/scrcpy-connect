import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/connection/connection_policy.dart';

void main() {
  test('QR 与单端点执行预算在创建任何发现或握手前拒绝无效期限', () {
    for (final policy in [
      const ConnectionPolicy(qrPairingTimeout: Duration.zero),
      const ConnectionPolicy(endpointTimeout: Duration(microseconds: -1)),
      const ConnectionPolicy(tcpipRestartTimeout: Duration(days: 2)),
    ]) {
      expect(policy.validate, throwsArgumentError);
    }
  });
  test('产品 TCP 默认值只由应用传入，通用 ADB 默认不启用 keepalive 或 burst', () {
    const mechanism = AdbConnectOptions();
    const policy = ConnectionPolicy();
    final execution = policy.directConnectOptions(burstMode: true);
    execution.validate();
    expect(mechanism.burstMode, isFalse);
    expect(mechanism.tcp.keepalive, isNull);
    expect(mechanism.tcp.userTimeout, isNull);
    expect(execution.burstMode, isTrue);
    expect(execution.publicKeyComment, 'interop-controller');
    expect(execution.tcp.keepalive!.idle, const Duration(seconds: 1));
    expect(execution.tcp.keepalive!.interval, const Duration(seconds: 1));
    expect(execution.tcp.keepalive!.retries, 10);
    expect(execution.tcp.userTimeout, const Duration(seconds: 11));
    expect(policy.directConnectOptions(burstMode: false).burstMode, isFalse);
  });
}
