// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'app_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppStore)
final appStoreProvider = AppStoreProvider._();

final class AppStoreProvider extends $NotifierProvider<AppStore, AppState> {
  AppStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appStoreHash();

  @$internal
  @override
  AppStore create() => AppStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppState>(value),
    );
  }
}

String _$appStoreHash() => r'6b44401b4b43478a80d2eefcdfe3ce7832e6da5f';

abstract class _$AppStore extends $Notifier<AppState> {
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
