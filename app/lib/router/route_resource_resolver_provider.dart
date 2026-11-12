import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';

import 'route_resource_resolver.dart';

export 'route_resource_resolver.dart';

part 'route_resource_resolver_provider.g.dart';

@Riverpod(keepAlive: true)
RouteResourceResolver routeResourceResolver(Ref ref) =>
    RouteResourceResolver(ref.watch(appProvider.notifier));
