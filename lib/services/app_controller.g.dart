// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'app_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppController)
final appControllerProvider = AppControllerProvider._();

final class AppControllerProvider
    extends $NotifierProvider<AppController, AppState> {
  AppControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appControllerHash();

  @$internal
  @override
  AppController create() => AppController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppState>(value),
    );
  }
}

String _$appControllerHash() => r'75370398009f7dfa7b6ecda3d78fb1dc90c1e6cb';

abstract class _$AppController extends $Notifier<AppState> {
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
