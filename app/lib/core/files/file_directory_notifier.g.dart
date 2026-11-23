// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'file_directory_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。

@ProviderFor(FileDirectoryNotifier)
final fileDirectoryProvider = FileDirectoryNotifierFamily._();

/// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。
final class FileDirectoryNotifierProvider
    extends $NotifierProvider<FileDirectoryNotifier, FileDirectoryState> {
  /// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。
  FileDirectoryNotifierProvider._({
    required FileDirectoryNotifierFamily super.from,
    required FileDirectoryTarget super.argument,
  }) : super(
         retry: null,
         name: r'fileDirectoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileDirectoryNotifierHash();

  @override
  String toString() {
    return r'fileDirectoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileDirectoryNotifier create() => FileDirectoryNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileDirectoryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileDirectoryState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileDirectoryNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileDirectoryNotifierHash() =>
    r'c8ba219f2d14eb677e35434111007c863a4f4261';

/// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。

final class FileDirectoryNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          FileDirectoryNotifier,
          FileDirectoryState,
          FileDirectoryState,
          FileDirectoryState,
          FileDirectoryTarget
        > {
  FileDirectoryNotifierFamily._()
    : super(
        retry: null,
        name: r'fileDirectoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。

  FileDirectoryNotifierProvider call(FileDirectoryTarget target) =>
      FileDirectoryNotifierProvider._(argument: target, from: this);

  @override
  String toString() => r'fileDirectoryProvider';
}

/// 同一目录共享读取；失效立即撤销操作资格，在途旧回执不能恢复资格。

abstract class _$FileDirectoryNotifier extends $Notifier<FileDirectoryState> {
  late final _$args = ref.$arg as FileDirectoryTarget;
  FileDirectoryTarget get target => _$args;

  FileDirectoryState build(FileDirectoryTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FileDirectoryState, FileDirectoryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileDirectoryState, FileDirectoryState>,
              FileDirectoryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
