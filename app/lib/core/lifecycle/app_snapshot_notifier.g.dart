// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'app_snapshot_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 跨能力原子只读投影；能力操作、状态写入和资源生命周期由各自所有者维护。

@ProviderFor(AppSnapshotNotifier)
final appSnapshotProvider = AppSnapshotNotifierProvider._();

/// 跨能力原子只读投影；能力操作、状态写入和资源生命周期由各自所有者维护。
final class AppSnapshotNotifierProvider
    extends $NotifierProvider<AppSnapshotNotifier, AppState> {
  /// 跨能力原子只读投影；能力操作、状态写入和资源生命周期由各自所有者维护。
  AppSnapshotNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appSnapshotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appSnapshotNotifierHash();

  @$internal
  @override
  AppSnapshotNotifier create() => AppSnapshotNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppState>(value),
    );
  }
}

String _$appSnapshotNotifierHash() =>
    r'cb29e85b3458c0e6dba3dff1620e63e6365068a5';

/// 跨能力原子只读投影；能力操作、状态写入和资源生命周期由各自所有者维护。

abstract class _$AppSnapshotNotifier extends $Notifier<AppState> {
  AppState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppState, AppState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppState, AppState>,
              AppState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
