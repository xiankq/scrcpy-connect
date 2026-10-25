import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  late NativeAdbApi api;

  setUpAll(() async {
    api = await createNativeScrcpyAdbApi();
  });

  test('真实 FRB 把本机已关闭端口映射为 connection_refused', () async {
    final endpoint = await _closedEndpoint();
    await expectLater(
      _connectServer(api, endpoint),
      throwsA(_code('connection_refused')),
    );
  });
}

Matcher _code(String code) =>
    isA<AdbException>().having((error) => error.code, 'code', code);

/// 短暂预留独立环回端口后关闭，不依赖公网路由或用户的 ADB 服务。
Future<String> _closedEndpoint() async {
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final endpoint = '127.0.0.1:${reservation.port}';
  await reservation.close();
  return endpoint;
}

/// 若测试意外收到成功，也必须精确回收该连接，不能让失败断言遗留资源。
Future<void> _connectServer(
  NativeAdbApi api,
  String endpoint, {
  int timeoutMs = 5000,
  String? handshakeId,
}) async {
  final device = await api.connectServer(
    endpoint,
    'connection-error-fixture',
    timeoutMs,
    handshakeId: handshakeId,
  );
  await api.disconnect(device.id);
}
