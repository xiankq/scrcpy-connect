import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/router/route_resource_resolver.dart';

export 'package:scrcpy_connect/router/route_resource_resolver.dart';

part 'route_resource_resolver_provider.g.dart';

@Riverpod(keepAlive: true)
RouteResourceResolver routeResourceResolver(Ref ref) {
  // 只读取该路由所需的能力，不因解析一个设备而挂载全部功能状态。
  Future<T> owned<S, T>(
    S Function() source,
    FutureOr<T> Function(S) read,
  ) async {
    const changed = RequestFailure('route_source_changed', '资源来源已变化，请重新核验此页面。');
    if (!ref.mounted) throw changed;
    final original = source();
    final result = await read(original);
    if (!ref.mounted || !identical(source(), original)) throw changed;
    return result;
  }

  return RouteResourceResolver(
    readDevice: (id) => owned(
      () => ref.read(deviceReaderProvider),
      (source) => source.readDevice(id),
    ),
    readTransfer: (id) => owned(
      () => ref.read(fileTransfersProvider),
      (source) => source.readTransfer(id),
    ),
    readSessions: (id) => owned(
      () => ref.read(videoSessionsProvider),
      (source) => source.readVideoSessions(deviceId: id),
    ),
    readDirectory: (target) => owned(
      () => ref.read(fileDirectoriesProvider),
      (source) => source.readDirectory(target),
    ),
    readShare: (id) => owned(
      () => ref.read(incomingSharesProvider),
      (_) => ref.read(shareInboxProvider.notifier).find(id),
    ),
  );
}
