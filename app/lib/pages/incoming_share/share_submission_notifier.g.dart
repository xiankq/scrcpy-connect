// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'share_submission_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。

@ProviderFor(ShareSubmissionNotifier)
final shareSubmissionProvider = ShareSubmissionNotifierFamily._();

/// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。
final class ShareSubmissionNotifierProvider
    extends $NotifierProvider<ShareSubmissionNotifier, ShareSubmissionState> {
  /// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。
  ShareSubmissionNotifierProvider._({
    required ShareSubmissionNotifierFamily super.from,
    required (String, {Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'shareSubmissionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shareSubmissionNotifierHash();

  @override
  String toString() {
    return r'shareSubmissionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ShareSubmissionNotifier create() => ShareSubmissionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShareSubmissionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShareSubmissionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShareSubmissionNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shareSubmissionNotifierHash() =>
    r'3920f372f8a745dd03b85349ce4e97190b852de7';

/// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。

final class ShareSubmissionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          ShareSubmissionNotifier,
          ShareSubmissionState,
          ShareSubmissionState,
          ShareSubmissionState,
          (String, {Object scope})
        > {
  ShareSubmissionNotifierFamily._()
    : super(
        retry: null,
        name: r'shareSubmissionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。

  ShareSubmissionNotifierProvider call(
    String shareId, {
    required Object scope,
  }) => ShareSubmissionNotifierProvider._(
    argument: (shareId, scope: scope),
    from: this,
  );

  @override
  String toString() => r'shareSubmissionProvider';
}

/// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。

abstract class _$ShareSubmissionNotifier
    extends $Notifier<ShareSubmissionState> {
  late final _$args = ref.$arg as (String, {Object scope});
  String get shareId => _$args.$1;
  Object get scope => _$args.scope;

  ShareSubmissionState build(String shareId, {required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShareSubmissionState, ShareSubmissionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShareSubmissionState, ShareSubmissionState>,
              ShareSubmissionState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, scope: _$args.scope),
    );
  }
}
