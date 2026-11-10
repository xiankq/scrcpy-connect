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

@ProviderFor(systemNotifications)
final systemNotificationsProvider = SystemNotificationsProvider._();

final class SystemNotificationsProvider
    extends
        $FunctionalProvider<
          SystemNotifications,
          SystemNotifications,
          SystemNotifications
        >
    with $Provider<SystemNotifications> {
  SystemNotificationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemNotificationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemNotificationsHash();

  @$internal
  @override
  $ProviderElement<SystemNotifications> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SystemNotifications create(Ref ref) {
    return systemNotifications(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SystemNotifications value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SystemNotifications>(value),
    );
  }
}

String _$systemNotificationsHash() =>
    r'871d4933a7e9524b0ecf83b21328361314edbf47';
