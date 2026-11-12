// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'recovery_state_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RecoveryStateNotifier)
final recoveryStateProvider = RecoveryStateNotifierProvider._();

final class RecoveryStateNotifierProvider
    extends $NotifierProvider<RecoveryStateNotifier, RecoveryState> {
  RecoveryStateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recoveryStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recoveryStateNotifierHash();

  @$internal
  @override
  RecoveryStateNotifier create() => RecoveryStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecoveryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecoveryState>(value),
    );
  }
}

String _$recoveryStateNotifierHash() =>
    r'1a50959664a440e65f3057650cfb41d8a2b9084a';

abstract class _$RecoveryStateNotifier extends $Notifier<RecoveryState> {
  RecoveryState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RecoveryState, RecoveryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RecoveryState, RecoveryState>,
              RecoveryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
