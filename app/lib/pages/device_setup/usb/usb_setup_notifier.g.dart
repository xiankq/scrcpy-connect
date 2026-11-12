// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'usb_setup_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。

@ProviderFor(UsbSetupNotifier)
final usbSetupProvider = UsbSetupNotifierFamily._();

/// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。
final class UsbSetupNotifierProvider
    extends $NotifierProvider<UsbSetupNotifier, UsbSetupState> {
  /// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。
  UsbSetupNotifierProvider._({
    required UsbSetupNotifierFamily super.from,
    required ({String? deviceId, Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'usbSetupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usbSetupNotifierHash();

  @override
  String toString() {
    return r'usbSetupProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  UsbSetupNotifier create() => UsbSetupNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsbSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsbSetupState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UsbSetupNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usbSetupNotifierHash() => r'cf81466c7fba534d4c36a9eab9e07ace1909ae72';

/// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。

final class UsbSetupNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          UsbSetupNotifier,
          UsbSetupState,
          UsbSetupState,
          UsbSetupState,
          ({String? deviceId, Object scope})
        > {
  UsbSetupNotifierFamily._()
    : super(
        retry: null,
        name: r'usbSetupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。

  UsbSetupNotifierProvider call({String? deviceId, required Object scope}) =>
      UsbSetupNotifierProvider._(
        argument: (deviceId: deviceId, scope: scope),
        from: this,
      );

  @override
  String toString() => r'usbSetupProvider';
}

/// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。

abstract class _$UsbSetupNotifier extends $Notifier<UsbSetupState> {
  late final _$args = ref.$arg as ({String? deviceId, Object scope});
  String? get deviceId => _$args.deviceId;
  Object get scope => _$args.scope;

  UsbSetupState build({String? deviceId, required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UsbSetupState, UsbSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UsbSetupState, UsbSetupState>,
              UsbSetupState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(deviceId: _$args.deviceId, scope: _$args.scope),
    );
  }
}
