enum AdbDiscoveryKind { pairing, tlsConnect, tcpConnect }

/// 仅表示当前广播候选，不代表设备身份、配对信任或存活连接。
final class AdbDiscoveryEndpoint {
  const AdbDiscoveryEndpoint({
    required this.kind,
    required this.serviceName,
    required this.instance,
    required this.hostname,
    required this.address,
    required this.port,
    required this.validUntil,
    required this.generation,
  });

  final AdbDiscoveryKind kind;
  final String serviceName, instance, hostname, address;
  final int port, generation;
  final DateTime validUntil;

  String get key => '$kind\n$serviceName\n$hostname\n$address\n$port';
}
