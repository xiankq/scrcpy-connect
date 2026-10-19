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
    final result = await controller.execute(InteropCommand.deviceInfo, {
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
    final task = await controller.execute(InteropCommand.transfersGet, {
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
          (await controller.execute(InteropCommand.sessionList, {
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
      (await controller.execute(InteropCommand.filesList, {
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
      (await controller.execute(InteropCommand.notificationsList, {
        'deviceId': deviceId,
      }))['notifications'],
    ).where((n) => n['id'] == id);
    if (matches.isEmpty) {
      throw const RequestFailure('missing_notification', '这条通知已失效，请返回通知列表核对。');
    }
    return matches.first;
  }

  /// A retained reply is text to check or copy, never a recovered remote action.
  Future<Json> notificationReply(String deviceId, String id) async {
    Json? retained() {
      if (controller.isDisposed()) return null;
      final key = controller
          .snapshot()
          .notificationReplies
          .keys
          .where((key) => key.deviceId == deviceId && key.notificationId == id)
          .lastOrNull;
      return key == null
          ? null
          : {
              'id': key.notificationId,
              'revision': key.revision,
              'title': '本机保留的回复',
              'localReplyOnly': true,
            };
    }

    try {
      final snapshot = await controller.execute(
        InteropCommand.notificationsList,
        {'deviceId': deviceId},
      );
      controller.reconcileNotificationReplies(deviceId, snapshot);
      final current = objects(snapshot['notifications'])
          .where((notification) => notification['id'] == id)
          .firstOrNull;
      if (snapshot['live'] == true && current != null) return current;
      final saved = retained();
      if (saved != null) return saved;
      throw const RequestFailure(
        'missing_notification',
        '这条通知已失效或无法核验，请返回通知列表核对。',
      );
    } catch (_) {
      final saved = retained();
      if (saved != null) return saved;
      rethrow;
    }
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
