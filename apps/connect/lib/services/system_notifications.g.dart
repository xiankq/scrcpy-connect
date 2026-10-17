// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'system_notifications.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(systemNotificationSink)
final systemNotificationSinkProvider = SystemNotificationSinkProvider._();

final class SystemNotificationSinkProvider
    extends
        $FunctionalProvider<
          SystemNotificationSink,
          SystemNotificationSink,
          SystemNotificationSink
        >
    with $Provider<SystemNotificationSink> {
  SystemNotificationSinkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemNotificationSinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemNotificationSinkHash();

  @$internal
  @override
  $ProviderElement<SystemNotificationSink> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SystemNotificationSink create(Ref ref) {
    return systemNotificationSink(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SystemNotificationSink value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SystemNotificationSink>(value),
    );
  }
}

String _$systemNotificationSinkHash() =>
    r'e677853c0908ec3055881a74a642eed418d8a964';

@ProviderFor(systemNotificationCoordinator)
final systemNotificationCoordinatorProvider =
    SystemNotificationCoordinatorProvider._();

final class SystemNotificationCoordinatorProvider
    extends
        $FunctionalProvider<
          SystemNotificationCoordinator,
          SystemNotificationCoordinator,
          SystemNotificationCoordinator
        >
    with $Provider<SystemNotificationCoordinator> {
  SystemNotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemNotificationCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemNotificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<SystemNotificationCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SystemNotificationCoordinator create(Ref ref) {
    return systemNotificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SystemNotificationCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SystemNotificationCoordinator>(
        value,
      ),
    );
  }
}

String _$systemNotificationCoordinatorHash() =>
    r'e36b5d65059e5e2f5071760b00a0533eaa6758a3';
