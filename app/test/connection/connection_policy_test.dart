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
}
