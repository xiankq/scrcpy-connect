// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'application_session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(applicationSession)
final applicationSessionProvider = ApplicationSessionProvider._();

final class ApplicationSessionProvider
    extends
        $FunctionalProvider<
          ApplicationSession,
          ApplicationSession,
          ApplicationSession
        >
    with $Provider<ApplicationSession> {
  ApplicationSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'applicationSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$applicationSessionHash();

  @$internal
  @override
  $ProviderElement<ApplicationSession> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ApplicationSession create(Ref ref) {
    return applicationSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApplicationSession value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApplicationSession>(value),
    );
  }
}

String _$applicationSessionHash() =>
    r'e2a0ebd34a6339d4d19659fa6fde80fa840bd295';
