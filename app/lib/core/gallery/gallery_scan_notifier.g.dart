// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'gallery_scan_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。

@ProviderFor(GalleryScanNotifier)
final galleryScanProvider = GalleryScanNotifierFamily._();

/// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。
final class GalleryScanNotifierProvider
    extends $NotifierProvider<GalleryScanNotifier, GalleryScanState> {
  /// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。
  GalleryScanNotifierProvider._({
    required GalleryScanNotifierFamily super.from,
    required (DeviceSnapshot, {Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'galleryScanProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$galleryScanNotifierHash();

  @override
  String toString() {
    return r'galleryScanProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  GalleryScanNotifier create() => GalleryScanNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GalleryScanState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GalleryScanState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GalleryScanNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$galleryScanNotifierHash() =>
    r'9a84cabc19c3f16e1825cb3174aeb6acb9588113';

/// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。

final class GalleryScanNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          GalleryScanNotifier,
          GalleryScanState,
          GalleryScanState,
          GalleryScanState,
          (DeviceSnapshot, {Object scope})
        > {
  GalleryScanNotifierFamily._()
    : super(
        retry: null,
        name: r'galleryScanProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。

  GalleryScanNotifierProvider call(
    DeviceSnapshot device, {
    required Object scope,
  }) => GalleryScanNotifierProvider._(
    argument: (device, scope: scope),
    from: this,
  );

  @override
  String toString() => r'galleryScanProvider';
}

/// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。

abstract class _$GalleryScanNotifier extends $Notifier<GalleryScanState> {
  late final _$args = ref.$arg as (DeviceSnapshot, {Object scope});
  DeviceSnapshot get device => _$args.$1;
  Object get scope => _$args.scope;

  GalleryScanState build(DeviceSnapshot device, {required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GalleryScanState, GalleryScanState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GalleryScanState, GalleryScanState>,
              GalleryScanState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, scope: _$args.scope),
    );
  }
}
