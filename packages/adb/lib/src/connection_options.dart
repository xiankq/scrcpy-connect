import 'dart:convert';

/// 直连 adbd 的执行选项；官方 adb-server 自行管理握手和设备 socket。
/// 默认值只对应协议机制，不包含应用的健康检查或重连策略。
final class AdbConnectOptions {
  const AdbConnectOptions({
    this.burstMode = false,
    this.publicKeyComment = 'interop-adb',
    this.tcp = const AdbTcpOptions(),
  });

  final bool burstMode;
  final String publicKeyComment;
  final AdbTcpOptions tcp;

  void validate() {
    if (utf8.encode(publicKeyComment).length > 1024 ||
        publicKeyComment.contains(RegExp(r'[\x00\r\n]'))) {
      throw ArgumentError.value(publicKeyComment, 'publicKeyComment');
    }
    tcp.validate();
  }
}

/// 仅配置本次新建的 TCP socket，不改变已经建立的连接。
final class AdbTcpOptions {
  const AdbTcpOptions({this.nodelay = true, this.keepalive, this.userTimeout});

  final bool nodelay;
  final AdbKeepaliveOptions? keepalive;

  /// Linux、Android 支持 TCP_USER_TIMEOUT；其他宿主不能应用此选项。
  final Duration? userTimeout;

  void validate() {
    keepalive?.validate();
    if (userTimeout case final value?) {
      _positiveMillis(value, 'userTimeout', maximum: 0x7fffffff);
    }
  }
}

final class AdbKeepaliveOptions {
  const AdbKeepaliveOptions({
    required this.idle,
    required this.interval,
    required this.retries,
  });

  final Duration idle;
  final Duration interval;
  final int retries;

  void validate() {
    _positiveMillis(idle, 'idle', minimum: 1000, maximum: 32767000);
    _positiveMillis(interval, 'interval', minimum: 1000, maximum: 32767000);
    if (retries <= 0 || retries > 127) {
      throw ArgumentError.value(retries, 'retries');
    }
  }
}

void _positiveMillis(
  Duration value,
  String name, {
  int minimum = 1,
  required int maximum,
}) {
  if (value.inMicroseconds % Duration.microsecondsPerMillisecond != 0 ||
      value.inMilliseconds < minimum ||
      value.inMilliseconds > maximum) {
    throw ArgumentError.value(value, name, '须为 $minimum 至 $maximum 范围内的整数毫秒');
  }
}
