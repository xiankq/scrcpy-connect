// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_list_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DeviceListNotifier)
final deviceListProvider = DeviceListNotifierProvider._();

final class DeviceListNotifierProvider
    extends $NotifierProvider<DeviceListNotifier, DeviceListState> {
  DeviceListNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceListNotifierHash();

  @$internal
  @override
  DeviceListNotifier create() => DeviceListNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceListState>(value),
    );
  }
}

String _$deviceListNotifierHash() =>
    r'6ec0e5f890649c2cf7aff7c430df8d81cb616b02';

abstract class _$DeviceListNotifier extends $Notifier<DeviceListState> {
  DeviceListState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DeviceListState, DeviceListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DeviceListState, DeviceListState>,
              DeviceListState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
