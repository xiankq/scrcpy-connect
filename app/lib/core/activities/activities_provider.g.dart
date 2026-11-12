// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'activities_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(activities)
final activitiesProvider = ActivitiesFamily._();

final class ActivitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<ActivityCollection>,
          ActivityCollection,
          FutureOr<ActivityCollection>
        >
    with
        $FutureModifier<ActivityCollection>,
        $FutureProvider<ActivityCollection> {
  ActivitiesProvider._({
    required ActivitiesFamily super.from,
    required String? super.argument,
  }) : super(
         retry: _noRetry,
         name: r'activitiesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activitiesHash();

  @override
  String toString() {
    return r'activitiesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ActivityCollection> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ActivityCollection> create(Ref ref) {
    final argument = this.argument as String?;
    return activities(ref, deviceId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivitiesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activitiesHash() => r'7fa28d0717bb9ef2b65c21b27323891556864952';

final class ActivitiesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ActivityCollection>, String?> {
  ActivitiesFamily._()
    : super(
        retry: _noRetry,
        name: r'activitiesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ActivitiesProvider call({String? deviceId}) =>
      ActivitiesProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'activitiesProvider';
}
