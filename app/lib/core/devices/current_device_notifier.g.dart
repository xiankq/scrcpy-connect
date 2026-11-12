// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'current_device_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 当前操作设备归用户焦点选择，不属于宿主恢复状态。

@ProviderFor(CurrentDeviceNotifier)
final currentDeviceProvider = CurrentDeviceNotifierProvider._();

/// 当前操作设备归用户焦点选择，不属于宿主恢复状态。
final class CurrentDeviceNotifierProvider
    extends $NotifierProvider<CurrentDeviceNotifier, String?> {
  /// 当前操作设备归用户焦点选择，不属于宿主恢复状态。
  CurrentDeviceNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentDeviceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentDeviceNotifierHash();

  @$internal
  @override
  CurrentDeviceNotifier create() => CurrentDeviceNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$currentDeviceNotifierHash() =>
    r'c5d672918fcee6d6b3de97277e0469c5ffdeff34';

/// 当前操作设备归用户焦点选择，不属于宿主恢复状态。

abstract class _$CurrentDeviceNotifier extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
