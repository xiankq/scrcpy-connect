// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'route_resource_resolver.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(routeResourceResolver)
final routeResourceResolverProvider = RouteResourceResolverProvider._();

final class RouteResourceResolverProvider
    extends
        $FunctionalProvider<
          RouteResourceResolver,
          RouteResourceResolver,
          RouteResourceResolver
        >
    with $Provider<RouteResourceResolver> {
  RouteResourceResolverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeResourceResolverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeResourceResolverHash();

  @$internal
  @override
  $ProviderElement<RouteResourceResolver> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RouteResourceResolver create(Ref ref) {
    return routeResourceResolver(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RouteResourceResolver value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RouteResourceResolver>(value),
    );
  }
}

String _$routeResourceResolverHash() =>
    r'e7bd6e90e11507f18c25291a5bb888537127947d';
