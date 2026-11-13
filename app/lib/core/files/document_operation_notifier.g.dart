// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'document_operation_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。

@ProviderFor(DocumentOperationNotifier)
final documentOperationProvider = DocumentOperationNotifierFamily._();

/// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。
final class DocumentOperationNotifierProvider
    extends
        $NotifierProvider<DocumentOperationNotifier, DocumentOperationState> {
  /// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。
  DocumentOperationNotifierProvider._({
    required DocumentOperationNotifierFamily super.from,
    required ({Object scope, DocumentSource? exportSource}) super.argument,
  }) : super(
         retry: null,
         name: r'documentOperationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$documentOperationNotifierHash();

  @override
  String toString() {
    return r'documentOperationProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  DocumentOperationNotifier create() => DocumentOperationNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DocumentOperationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DocumentOperationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentOperationNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$documentOperationNotifierHash() =>
    r'37f46f58d15b807f0c128171288ec04042bc1732';

/// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。

final class DocumentOperationNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          DocumentOperationNotifier,
          DocumentOperationState,
          DocumentOperationState,
          DocumentOperationState,
          ({Object scope, DocumentSource? exportSource})
        > {
  DocumentOperationNotifierFamily._()
    : super(
        retry: null,
        name: r'documentOperationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。

  DocumentOperationNotifierProvider call({
    required Object scope,
    DocumentSource? exportSource,
  }) => DocumentOperationNotifierProvider._(
    argument: (scope: scope, exportSource: exportSource),
    from: this,
  );

  @override
  String toString() => r'documentOperationProvider';
}

/// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。

abstract class _$DocumentOperationNotifier
    extends $Notifier<DocumentOperationState> {
  late final _$args =
      ref.$arg as ({Object scope, DocumentSource? exportSource});
  Object get scope => _$args.scope;
  DocumentSource? get exportSource => _$args.exportSource;

  DocumentOperationState build({
    required Object scope,
    DocumentSource? exportSource,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DocumentOperationState, DocumentOperationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DocumentOperationState, DocumentOperationState>,
              DocumentOperationState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(scope: _$args.scope, exportSource: _$args.exportSource),
    );
  }
}
