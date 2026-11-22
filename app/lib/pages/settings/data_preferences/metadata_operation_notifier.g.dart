// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'metadata_operation_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。

@ProviderFor(MetadataOperationNotifier)
final metadataOperationProvider = MetadataOperationNotifierFamily._();

/// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。
final class MetadataOperationNotifierProvider
    extends
        $NotifierProvider<MetadataOperationNotifier, MetadataOperationState> {
  /// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。
  MetadataOperationNotifierProvider._({
    required MetadataOperationNotifierFamily super.from,
    required Object super.argument,
  }) : super(
         retry: null,
         name: r'metadataOperationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$metadataOperationNotifierHash();

  @override
  String toString() {
    return r'metadataOperationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MetadataOperationNotifier create() => MetadataOperationNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataOperationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataOperationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MetadataOperationNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$metadataOperationNotifierHash() =>
    r'befa3f93188dc5b80622bfd42b0131be1b8ddfb7';

/// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。

final class MetadataOperationNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          MetadataOperationNotifier,
          MetadataOperationState,
          MetadataOperationState,
          MetadataOperationState,
          Object
        > {
  MetadataOperationNotifierFamily._()
    : super(
        retry: null,
        name: r'metadataOperationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。

  MetadataOperationNotifierProvider call({required Object scope}) =>
      MetadataOperationNotifierProvider._(argument: scope, from: this);

  @override
  String toString() => r'metadataOperationProvider';
}

/// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。

abstract class _$MetadataOperationNotifier
    extends $Notifier<MetadataOperationState> {
  late final _$args = ref.$arg as Object;
  Object get scope => _$args;

  MetadataOperationState build({required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<MetadataOperationState, MetadataOperationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MetadataOperationState, MetadataOperationState>,
              MetadataOperationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(scope: _$args));
  }
}
