import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/models/adb_discovery_endpoint.dart';

/// 已保存 GUID 的候选读取与代次核验；广播只提供位置，不授予设备信任。
abstract interface class DeviceReconnectionCandidates {
  factory DeviceReconnectionCandidates.mdns(
    DeviceDiscovery Function() discovery,
  ) = _MdnsDeviceReconnectionCandidates;
  Future<List<AdbDiscoveryEndpoint>> resolve(
    String guid, {
    required AdbCancellation cancellation,
  });

  bool isCurrent(AdbDiscoveryEndpoint endpoint);
}

/// 复用应用发现所有者，只保留同一 GUID 的 TLS 服务，精确实例优先。
final class _MdnsDeviceReconnectionCandidates
    implements DeviceReconnectionCandidates {
  _MdnsDeviceReconnectionCandidates(this._readDiscovery);

  final DeviceDiscovery Function() _readDiscovery;
  DeviceDiscovery? _discovery;

  @override
  Future<List<AdbDiscoveryEndpoint>> resolve(
    String guid, {
    required AdbCancellation cancellation,
  }) async {
    cancellation.check();
    final discovery = _discovery ??= _readDiscovery();
    final found = await discovery.scan(cancellation: cancellation);
    cancellation.check();
    final matching =
        found
            .where(
              (endpoint) =>
                  endpoint.kind == AdbDiscoveryKind.tlsConnect &&
                  DeviceDiscovery.matchesGuid(endpoint.instance, guid) &&
                  discovery.isCurrent(endpoint),
            )
            .toList()
          ..sort((a, b) {
            final exact = (a.instance == guid ? 0 : 1).compareTo(
              b.instance == guid ? 0 : 1,
            );
            if (exact != 0) return exact;
            final service = a.serviceName.compareTo(b.serviceName);
            if (service != 0) return service;
            return '${a.address}:${a.port}'.compareTo('${b.address}:${b.port}');
          });
    final services = <String>{};
    return List.unmodifiable(
      matching.where((endpoint) {
        if (services.contains(endpoint.serviceName)) return true;
        if (services.length == 8) return false;
        services.add(endpoint.serviceName);
        return true;
      }),
    );
  }

  @override
  bool isCurrent(AdbDiscoveryEndpoint endpoint) =>
      _discovery?.isCurrent(endpoint) ?? false;
}
