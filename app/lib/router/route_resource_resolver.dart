import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

part 'route_resource_resolver.g.dart';

@Riverpod(keepAlive: true)
RouteResourceResolver routeResourceResolver(Ref ref) =>
    RouteResourceResolver(ref.watch(appControllerProvider.notifier));

/// 按路由参数解析并核验当前资源；标识只用于定位，不代表授权或信任。
class RouteResourceResolver {
  RouteResourceResolver(this.controller);
  final AppController controller;
  Future<Json> device(String id) async {
    if (id.isEmpty) {
      throw const RequestFailure('missing_device', '没有指定设备，请从设备列表重新打开。');
    }
    final result = await controller.execute(ApplicationCommand.deviceInfo, {
      'deviceId': id,
    });
    final device = result['device'] is Map<Object?, Object?>
        ? jsonObject(result['device'])
        : result;
    if (device['id'] != id) {
      throw const RequestFailure('missing_device', '设备记录已移除或无法读取，请返回设备列表重新选择。');
    }
    return device;
  }

  Future<Json> transfer(String id) async {
    final task = await controller.execute(ApplicationCommand.transfersGet, {
      'transferId': id,
    });
    if (value(task, 'id', value(task, 'transferId')) != id) {
      throw const RequestFailure('missing_transfer', '传输记录已不存在，请在传输中心重新选择。');
    }
    return task;
  }

  Future<Json> session(String deviceId, String id) async {
    final matches =
        objects(
          (await controller.execute(ApplicationCommand.sessionList, {
            'deviceId': deviceId,
          }))['sessions'],
        ).where(
          (s) =>
              value(s, 'sessionId', value(s, 'id')) == id &&
              s['deviceId'] == deviceId &&
              s['status'] != 'stopped',
        );
    if (matches.isEmpty) {
      throw const RequestFailure(
        'missing_session',
        '这个控制会话已结束。请从设备工作台明确打开新的画面。',
      );
    }
    return matches.first;
  }

  Future<Json> file(String deviceId, String path) async {
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw const RequestFailure('invalid_path', '文件位置无效，请从文件目录重新打开。');
    }
    final separator = path.lastIndexOf('/');
    final parent = separator <= 0 ? '/' : path.substring(0, separator);
    final matches = objects(
      (await controller.execute(ApplicationCommand.filesList, {
        'deviceId': deviceId,
        'path': parent,
      }))['entries'],
    ).where((f) => f['path'] == path);
    if (matches.isEmpty) {
      throw const RequestFailure('missing_file', '文件已移动、移除或无法读取，请返回目录刷新。');
    }
    return matches.first;
  }

  Future<Json> share(String id) async {
    await controller.loadPendingShares();
    final matches = controller.snapshot().pendingShares.where(
      (s) => s['shareId'] == id,
    );
    if (matches.isEmpty) {
      throw const RequestFailure('missing_share', '这次分享已处理或不在本机队列中，请重新从系统分享。');
    }
    return matches.first;
  }
}
