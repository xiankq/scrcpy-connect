// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_search_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。

@ProviderFor(FileSearchNotifier)
final fileSearchProvider = FileSearchNotifierFamily._();

/// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。
final class FileSearchNotifierProvider
    extends $NotifierProvider<FileSearchNotifier, FileSearchState> {
  /// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。
  FileSearchNotifierProvider._({
    required FileSearchNotifierFamily super.from,
    required (String, {Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'fileSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileSearchNotifierHash();

  @override
  String toString() {
    return r'fileSearchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  FileSearchNotifier create() => FileSearchNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileSearchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileSearchNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileSearchNotifierHash() =>
    r'020b2d71b40388c7ea72d09a60df43a45137df29';

/// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。

final class FileSearchNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          FileSearchNotifier,
          FileSearchState,
          FileSearchState,
          FileSearchState,
          (String, {Object scope})
        > {
  FileSearchNotifierFamily._()
    : super(
        retry: null,
        name: r'fileSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。

  FileSearchNotifierProvider call(String deviceId, {required Object scope}) =>
      FileSearchNotifierProvider._(
        argument: (deviceId, scope: scope),
        from: this,
      );

  @override
  String toString() => r'fileSearchProvider';
}

/// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。

abstract class _$FileSearchNotifier extends $Notifier<FileSearchState> {
  late final _$args = ref.$arg as (String, {Object scope});
  String get deviceId => _$args.$1;
  Object get scope => _$args.scope;

  FileSearchState build(String deviceId, {required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FileSearchState, FileSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileSearchState, FileSearchState>,
              FileSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, scope: _$args.scope),
    );
  }
}
