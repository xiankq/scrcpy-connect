// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'system_notification_sink_provider.dart';

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
