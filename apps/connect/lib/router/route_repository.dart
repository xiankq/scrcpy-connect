import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

part 'route_repository.g.dart';

@Riverpod(keepAlive: true)
RouteRepository routeRepository(Ref ref) =>
    RouteRepository(ref.watch(appControllerProvider.notifier));

/// Route identifiers are locators, never snapshots of authorization or trust.
/// Every production lookup resolves the current record through the JSON bridge.
class RouteRepository {
  RouteRepository(this.controller);
  final AppController controller;
  Future<Json> device(String id) async {
    if (id.isEmpty) {
      throw const RequestFailure('missing_device', '没有指定设备，请从设备列表重新打开。');
    }
    final result = await controller.request('device.info', {'deviceId': id});
    final device = result['device'] is Map<Object?, Object?>
        ? jsonObject(result['device'])
        : result;
    if (device['id'] != id) {
      throw const RequestFailure('missing_device', '设备记录已移除或无法读取，请返回设备列表重新选择。');
    }
    return device;
  }

  Future<Json> transfer(String id) async {
    final task = await controller.request('transfers.get', {'transferId': id});
    if (value(task, 'id', value(task, 'transferId')) != id) {
      throw const RequestFailure('missing_transfer', '传输记录已不存在，请在传输中心重新选择。');
    }
    return task;
  }

  Future<Json> session(String deviceId, String id) async {
    final matches =
        objects(
          (await controller.request('session.list', {
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
      (await controller.request('files.list', {
        'deviceId': deviceId,
        'path': parent,
      }))['entries'],
    ).where((f) => f['path'] == path);
    if (matches.isEmpty) {
      throw const RequestFailure('missing_file', '文件已移动、移除或无法读取，请返回目录刷新。');
    }
    return matches.first;
  }

  Future<Json> notification(String deviceId, String id) async {
    final matches = objects(
      (await controller.request('notifications.list', {
        'deviceId': deviceId,
      }))['notifications'],
    ).where((n) => n['id'] == id);
    if (matches.isEmpty) {
      throw const RequestFailure('missing_notification', '这条通知已失效，请返回通知列表核对。');
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
