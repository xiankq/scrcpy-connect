// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_actions_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。

@ProviderFor(FileActionsNotifier)
final fileActionsProvider = FileActionsNotifierFamily._();

/// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。
final class FileActionsNotifierProvider
    extends $NotifierProvider<FileActionsNotifier, FileActionState> {
  /// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。
  FileActionsNotifierProvider._({
    required FileActionsNotifierFamily super.from,
    required (FileDirectoryTarget, {Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'fileActionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileActionsNotifierHash();

  @override
  String toString() {
    return r'fileActionsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  FileActionsNotifier create() => FileActionsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileActionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileActionsNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileActionsNotifierHash() =>
    r'7951f36b89c933ded54890dff01303964b8cb05a';

/// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。

final class FileActionsNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          FileActionsNotifier,
          FileActionState,
          FileActionState,
          FileActionState,
          (FileDirectoryTarget, {Object scope})
        > {
  FileActionsNotifierFamily._()
    : super(
        retry: null,
        name: r'fileActionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。

  FileActionsNotifierProvider call(
    FileDirectoryTarget target, {
    required Object scope,
  }) => FileActionsNotifierProvider._(
    argument: (target, scope: scope),
    from: this,
  );

  @override
  String toString() => r'fileActionsProvider';
}

/// 单个文件页面的操作编排；离页撤销回执交付，不取消已登记的核心操作。

abstract class _$FileActionsNotifier extends $Notifier<FileActionState> {
  late final _$args = ref.$arg as (FileDirectoryTarget, {Object scope});
  FileDirectoryTarget get target => _$args.$1;
  Object get scope => _$args.scope;

  FileActionState build(FileDirectoryTarget target, {required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FileActionState, FileActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileActionState, FileActionState>,
              FileActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, scope: _$args.scope),
    );
  }
}
