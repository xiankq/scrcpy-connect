/// Application connection defaults. Rust owns execution and resource lifetimes.
/// Changing this policy requires restarting the process; it never renegotiates
/// a live device connection.
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
    this.tcp = const AdbTcpOptions(),
    this.healthEnabled = true,
    this.healthIdle = const Duration(seconds: 10),
    this.healthProbeTimeout = const Duration(seconds: 3),
    this.healthFailureLimit = 2,
    this.monitorInterval = const Duration(seconds: 2),
    this.reconnectEnabled = true,
    this.reconnectInitialDelay = const Duration(seconds: 2),
    this.reconnectMaxDelay = const Duration(seconds: 64),
  });

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
  final AdbTcpOptions tcp;
  final bool healthEnabled;
  final Duration healthIdle;
  final Duration healthProbeTimeout;
  final int healthFailureLimit;
  final Duration monitorInterval;
  final bool reconnectEnabled;
  final Duration reconnectInitialDelay;
  final Duration reconnectMaxDelay;

  void validate() {
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

  /// Only execution settings cross the native boundary. Retry policy stays in Dart.
  Map<String, Object?> toNativeJson() => Map<String, Object?>.from(toJson())
    ..remove('setupLeaseTimeoutMs')
    ..remove('setupPollIntervalMs')
    ..remove('pairingDiscoveryRetries')
    ..remove('probeTimeoutMs')
    ..remove('pairingDiscoveryTimeoutMs')
    ..remove('tcpipReconnectTimeoutMs')
    ..remove('tcpipRetryIntervalMs')
    ..remove('reconnectEnabled')
    ..remove('reconnectInitialDelayMs')
    ..remove('reconnectMaxDelayMs');

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
    'tcp': tcp.toJson(),
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

/// Raw TCP socket configuration, independent of ADB authentication or retry.
class AdbTcpOptions {
  const AdbTcpOptions({
    this.nodelay = true,
    this.keepalive = const AdbKeepaliveOptions(),
    this.userTimeout = const Duration(seconds: 11),
  });

  final bool nodelay;
  final AdbKeepaliveOptions? keepalive;

  /// Applied on Android/Linux; unavailable on other hosts.
  final Duration? userTimeout;

  Map<String, Object?> toJson() => {
    'nodelay': nodelay,
    'keepalive': keepalive?.toJson(),
    'userTimeoutMs': userTimeout?.inMilliseconds,
  };
}

class AdbKeepaliveOptions {
  const AdbKeepaliveOptions({
    this.idle = const Duration(seconds: 1),
    this.interval = const Duration(seconds: 1),
    this.retries = 10,
  });

  final Duration idle;
  final Duration interval;
  final int retries;

  Map<String, Object?> toJson() => {
    'idleMs': idle.inMilliseconds,
    'intervalMs': interval.inMilliseconds,
    'retries': retries,
  };
}
