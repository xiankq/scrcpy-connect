import 'package:adb/adb.dart' show AdbCancellation;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';

part 'device_discovery_provider.g.dart';

/// 同一 scope 共享扫描；离开页面或更换依赖时撤销旧扫描，重试由用户发起。
@Riverpod(retry: _noRetry)
Future<List<DiscoveredDevice>> deviceDiscovery(Ref ref) {
  final setup = ref.watch(deviceSetupProvider);
  final cancellation = AdbCancellation();
  ref.onDispose(cancellation.cancel);
  return setup.discoverDevices(cancellation: cancellation);
}

Duration? _noRetry(int _, Object _) => null;
