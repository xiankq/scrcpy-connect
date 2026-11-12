// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'cache_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同一 scope 共享占用核验；依赖替换或缓存变更使旧回执失效。

@ProviderFor(cacheStatus)
final cacheStatusProvider = CacheStatusProvider._();

/// 同一 scope 共享占用核验；依赖替换或缓存变更使旧回执失效。

final class CacheStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<CacheStatus>,
          CacheStatus,
          FutureOr<CacheStatus>
        >
    with $FutureModifier<CacheStatus>, $FutureProvider<CacheStatus> {
  /// 同一 scope 共享占用核验；依赖替换或缓存变更使旧回执失效。
  CacheStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'cacheStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cacheStatusHash();

  @$internal
  @override
  $FutureProviderElement<CacheStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CacheStatus> create(Ref ref) {
    return cacheStatus(ref);
  }
}

String _$cacheStatusHash() => r'8ae276c4388ad6f5925fba4cef47a2201cbeb704';
