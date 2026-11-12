// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'state_subscription_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(stateSubscription)
final stateSubscriptionProvider = StateSubscriptionProvider._();

final class StateSubscriptionProvider
    extends
        $FunctionalProvider<
          StateSubscription,
          StateSubscription,
          StateSubscription
        >
    with $Provider<StateSubscription> {
  StateSubscriptionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stateSubscriptionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stateSubscriptionHash();

  @$internal
  @override
  $ProviderElement<StateSubscription> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StateSubscription create(Ref ref) {
    return stateSubscription(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StateSubscription value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StateSubscription>(value),
    );
  }
}

String _$stateSubscriptionHash() => r'74541bd9388cfbe4b73729a0454c880a4955e196';
