import 'dart:io';

import 'package:adb/adb.dart'
    show AdbConnectOptions, AdbTcpOptions, AdbKeepaliveOptions;

export 'package:adb/adb.dart' show AdbTcpOptions, AdbKeepaliveOptions;

/// 应用拥有连接默认值、健康检查与重试策略；执行参数使用能力包的类型。
/// 修改策略需要重启进程，不重新协商存活连接。
class ConnectionPolicy {
  const ConnectionPolicy({
    this.setupLeaseTimeout = const Duration(minutes: 5),
    this.setupPollInterval = const Duration(milliseconds: 100),
    this.pairingDiscoveryRetries = 3,
    this.probeTimeout = const Duration(seconds: 5),
    this.requestAuthorization = true,
    this.publicKeyComment = 'interop-controller',
    this.connectTimeout = const Duration(seconds: 60),
    this.discoveryTimeout = const Duration(seconds: 3),
    this.pairingTimeout = const Duration(seconds: 60),
    this.qrPairingTimeout = const Duration(seconds: 120),
    this.pairingDiscoveryTimeout = const Duration(seconds: 5),
    this.endpointTimeout = const Duration(seconds: 5),
    this.tcpipRestartTimeout = const Duration(seconds: 10),
    this.tcpipReconnectTimeout = const Duration(seconds: 20),
    this.tcpipRetryInterval = const Duration(milliseconds: 300),
    this.tcpipAttemptTimeout = const Duration(seconds: 4),
    this._tcp,
    this.healthEnabled = true,
    this.healthIdle = const Duration(seconds: 10),
    this.healthProbeTimeout = const Duration(seconds: 3),
    this.healthFailureLimit = 2,
    this.monitorInterval = const Duration(seconds: 2),
    this.reconnectEnabled = true,
    this.reconnectInitialDelay = const Duration(seconds: 2),
    this.reconnectMaxDelay = const Duration(seconds: 64),
  });

  static final _defaultTcp = AdbTcpOptions(
    keepalive: const AdbKeepaliveOptions(
      idle: Duration(seconds: 1),
      interval: Duration(seconds: 1),
      retries: 10,
    ),
    userTimeout: Platform.isAndroid || Platform.isLinux
        ? const Duration(seconds: 11)
        : null,
  );

  final Duration setupLeaseTimeout;
  final Duration setupPollInterval;
  final int pairingDiscoveryRetries;
  final Duration probeTimeout;
  final bool requestAuthorization;
  final String publicKeyComment;
  final Duration connectTimeout;
  final Duration discoveryTimeout;
  final Duration pairingTimeout;
  final Duration qrPairingTimeout;
  final Duration pairingDiscoveryTimeout;
  final Duration endpointTimeout;
  final Duration tcpipRestartTimeout;
  final Duration tcpipReconnectTimeout;
  final Duration tcpipRetryInterval;
  final Duration tcpipAttemptTimeout;
  final AdbTcpOptions? _tcp;
  AdbTcpOptions get tcp => _tcp ?? _defaultTcp;
  final bool healthEnabled;
  final Duration healthIdle;
  final Duration healthProbeTimeout;
  final int healthFailureLimit;
  final Duration monitorInterval;
  final bool reconnectEnabled;
  final Duration reconnectInitialDelay;
  final Duration reconnectMaxDelay;

  /// 每次新建直连时显式传入；burst 开关来自应用当次偏好，不影响存活连接。
  AdbConnectOptions directConnectOptions({required bool burstMode}) =>
      AdbConnectOptions(
        burstMode: burstMode,
        publicKeyComment: publicKeyComment,
        tcp: tcp,
      );

  void validate() {
    directConnectOptions(burstMode: false).validate();
    for (final timeout in [
      connectTimeout,
      discoveryTimeout,
      pairingTimeout,
      qrPairingTimeout,
      endpointTimeout,
      tcpipRestartTimeout,
      tcpipAttemptTimeout,
    ]) {
      if (timeout <= Duration.zero || timeout > const Duration(days: 1)) {
        throw ArgumentError('连接执行期限必须为正值且不超过一天。');
      }
    }
    if (setupLeaseTimeout <= Duration.zero ||
        setupLeaseTimeout > const Duration(days: 1) ||
        setupPollInterval <= Duration.zero ||
        pairingDiscoveryRetries < 1 ||
        pairingDiscoveryRetries > 100 ||
        probeTimeout <= Duration.zero ||
        probeTimeout > const Duration(minutes: 1) ||
        pairingDiscoveryTimeout <= Duration.zero ||
        tcpipReconnectTimeout <= Duration.zero ||
        tcpipRetryInterval <= Duration.zero) {
      throw ArgumentError(
        'Setup execution budgets must be positive and bounded',
      );
    }
    if (reconnectInitialDelay <= Duration.zero ||
        reconnectMaxDelay < reconnectInitialDelay ||
        reconnectMaxDelay > const Duration(days: 1)) {
      throw ArgumentError(
        'Reconnect delays must be positive and bounded by one day',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'setupLeaseTimeoutMs': setupLeaseTimeout.inMilliseconds,
    'setupPollIntervalMs': setupPollInterval.inMilliseconds,
    'pairingDiscoveryRetries': pairingDiscoveryRetries,
    'probeTimeoutMs': probeTimeout.inMilliseconds,
    'requestAuthorization': requestAuthorization,
    'publicKeyComment': publicKeyComment,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'discoveryTimeoutMs': discoveryTimeout.inMilliseconds,
    'pairingTimeoutMs': pairingTimeout.inMilliseconds,
    'qrPairingTimeoutMs': qrPairingTimeout.inMilliseconds,
    'pairingDiscoveryTimeoutMs': pairingDiscoveryTimeout.inMilliseconds,
    'endpointTimeoutMs': endpointTimeout.inMilliseconds,
    'tcpipRestartTimeoutMs': tcpipRestartTimeout.inMilliseconds,
    'tcpipReconnectTimeoutMs': tcpipReconnectTimeout.inMilliseconds,
    'tcpipRetryIntervalMs': tcpipRetryInterval.inMilliseconds,
    'tcpipAttemptTimeoutMs': tcpipAttemptTimeout.inMilliseconds,
    'tcp': {
      'nodelay': tcp.nodelay,
      'keepalive': tcp.keepalive == null
          ? null
          : {
              'idleMs': tcp.keepalive!.idle.inMilliseconds,
              'intervalMs': tcp.keepalive!.interval.inMilliseconds,
              'retries': tcp.keepalive!.retries,
            },
      'userTimeoutMs': tcp.userTimeout?.inMilliseconds,
    },
    'healthEnabled': healthEnabled,
    'healthIdleMs': healthIdle.inMilliseconds,
    'healthProbeTimeoutMs': healthProbeTimeout.inMilliseconds,
    'healthFailureLimit': healthFailureLimit,
    'monitorIntervalMs': monitorInterval.inMilliseconds,
    'reconnectEnabled': reconnectEnabled,
    'reconnectInitialDelayMs': reconnectInitialDelay.inMilliseconds,
    'reconnectMaxDelayMs': reconnectMaxDelay.inMilliseconds,
  };
}
