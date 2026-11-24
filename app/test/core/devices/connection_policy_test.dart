import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';

void main() {
  test('默认 TCP 连接仅在支持的宿主设置用户超时', () {
    final tcp = const ConnectionPolicy()
        .directConnectOptions(burstMode: false)
        .tcp;

    expect(tcp.keepalive?.retries, 10);
    expect(
      tcp.userTimeout,
      Platform.isAndroid || Platform.isLinux
          ? const Duration(seconds: 11)
          : isNull,
    );
  });
}
