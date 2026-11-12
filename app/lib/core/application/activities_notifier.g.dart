// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'activities_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

@ProviderFor(ActivitiesNotifier)
final activitiesProvider = ActivitiesNotifierFamily._();

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
final class ActivitiesNotifierProvider
    extends $NotifierProvider<ActivitiesNotifier, ActivitiesState> {
  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
  ActivitiesNotifierProvider._({
    required ActivitiesNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'activitiesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activitiesNotifierHash();

  @override
  String toString() {
    return r'activitiesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ActivitiesNotifier create() => ActivitiesNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivitiesState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivitiesState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ActivitiesNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activitiesNotifierHash() =>
    r'c7114f27571ae96437e42480d05a74aa0dcc8750';

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

final class ActivitiesNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          ActivitiesNotifier,
          ActivitiesState,
          ActivitiesState,
          ActivitiesState,
          String?
        > {
  ActivitiesNotifierFamily._()
    : super(
        retry: null,
        name: r'activitiesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

  ActivitiesNotifierProvider call({String? deviceId}) =>
      ActivitiesNotifierProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'activitiesProvider';
}

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

abstract class _$ActivitiesNotifier extends $Notifier<ActivitiesState> {
  late final _$args = ref.$arg as String?;
  String? get deviceId => _$args;

  ActivitiesState build({String? deviceId});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActivitiesState, ActivitiesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActivitiesState, ActivitiesState>,
              ActivitiesState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(deviceId: _$args));
  }
}
