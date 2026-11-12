// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'app_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 跨能力只读投影及作用域入口；各能力独立拥有状态与异步写入。

@ProviderFor(AppNotifier)
final appProvider = AppNotifierProvider._();

/// 跨能力只读投影及作用域入口；各能力独立拥有状态与异步写入。
final class AppNotifierProvider
    extends $NotifierProvider<AppNotifier, AppState> {
  /// 跨能力只读投影及作用域入口；各能力独立拥有状态与异步写入。
  AppNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appNotifierHash();

  @$internal
  @override
  AppNotifier create() => AppNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppState>(value),
    );
  }
}

String _$appNotifierHash() => r'02830b304a2e4e5cb25fbb670ff5a5f8c929fc01';

/// 跨能力只读投影及作用域入口；各能力独立拥有状态与异步写入。

abstract class _$AppNotifier extends $Notifier<AppState> {
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
