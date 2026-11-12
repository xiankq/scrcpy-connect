// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_discovery_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同一 scope 共享扫描；离开页面或更换依赖时撤销旧扫描，重试由用户发起。

@ProviderFor(deviceDiscovery)
final deviceDiscoveryProvider = DeviceDiscoveryProvider._();

/// 同一 scope 共享扫描；离开页面或更换依赖时撤销旧扫描，重试由用户发起。

final class DeviceDiscoveryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DiscoveredDevice>>,
          List<DiscoveredDevice>,
          FutureOr<List<DiscoveredDevice>>
        >
    with
        $FutureModifier<List<DiscoveredDevice>>,
        $FutureProvider<List<DiscoveredDevice>> {
  /// 同一 scope 共享扫描；离开页面或更换依赖时撤销旧扫描，重试由用户发起。
  DeviceDiscoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'deviceDiscoveryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceDiscoveryHash();

  @$internal
  @override
  $FutureProviderElement<List<DiscoveredDevice>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DiscoveredDevice>> create(Ref ref) {
    return deviceDiscovery(ref);
  }
}

String _$deviceDiscoveryHash() => r'3c02ebded510a73c9acbf229977c4be863928301';
