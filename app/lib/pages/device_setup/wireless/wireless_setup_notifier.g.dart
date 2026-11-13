// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'wireless_setup_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。

@ProviderFor(WirelessSetupNotifier)
final wirelessSetupProvider = WirelessSetupNotifierFamily._();

/// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。
final class WirelessSetupNotifierProvider
    extends $NotifierProvider<WirelessSetupNotifier, WirelessSetupState> {
  /// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。
  WirelessSetupNotifierProvider._({
    required WirelessSetupNotifierFamily super.from,
    required ({String deviceId, Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'wirelessSetupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$wirelessSetupNotifierHash();

  @override
  String toString() {
    return r'wirelessSetupProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  WirelessSetupNotifier create() => WirelessSetupNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WirelessSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WirelessSetupState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WirelessSetupNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$wirelessSetupNotifierHash() =>
    r'b921a3902484da57161080c5cc8428e314d37c38';

/// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。

final class WirelessSetupNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          WirelessSetupNotifier,
          WirelessSetupState,
          WirelessSetupState,
          WirelessSetupState,
          ({String deviceId, Object scope})
        > {
  WirelessSetupNotifierFamily._()
    : super(
        retry: null,
        name: r'wirelessSetupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。

  WirelessSetupNotifierProvider call({
    required String deviceId,
    required Object scope,
  }) => WirelessSetupNotifierProvider._(
    argument: (deviceId: deviceId, scope: scope),
    from: this,
  );

  @override
  String toString() => r'wirelessSetupProvider';
}

/// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。

abstract class _$WirelessSetupNotifier extends $Notifier<WirelessSetupState> {
  late final _$args = ref.$arg as ({String deviceId, Object scope});
  String get deviceId => _$args.deviceId;
  Object get scope => _$args.scope;

  WirelessSetupState build({required String deviceId, required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WirelessSetupState, WirelessSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WirelessSetupState, WirelessSetupState>,
              WirelessSetupState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(deviceId: _$args.deviceId, scope: _$args.scope),
    );
  }
}
