// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'application_status_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ApplicationStatusNotifier)
final applicationStatusProvider = ApplicationStatusNotifierProvider._();

final class ApplicationStatusNotifierProvider
    extends $NotifierProvider<ApplicationStatusNotifier, ApplicationStatus> {
  ApplicationStatusNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'applicationStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$applicationStatusNotifierHash();

  @$internal
  @override
  ApplicationStatusNotifier create() => ApplicationStatusNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApplicationStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApplicationStatus>(value),
    );
  }
}

String _$applicationStatusNotifierHash() =>
    r'2f545fe7eb8b7bb5b99c8d65595859480dae1494';

abstract class _$ApplicationStatusNotifier
    extends $Notifier<ApplicationStatus> {
  ApplicationStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ApplicationStatus, ApplicationStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ApplicationStatus, ApplicationStatus>,
              ApplicationStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
