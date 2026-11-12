import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';

/// 按路由参数解析并核验当前资源；标识只用于定位，不代表授权或信任。
class RouteResourceResolver {
  RouteResourceResolver({
    required this._readDevice,
    required this._readTransfer,
    required this._readSessions,
    required this._readDirectory,
    required this._readShare,
  });
  final Future<DeviceSnapshot> Function(String) _readDevice;
  final Future<FileTransferSnapshot> Function(String) _readTransfer;
  final Future<List<VideoSessionView>> Function(String) _readSessions;
  final Future<FileDirectorySnapshot> Function(FileDirectoryTarget)
  _readDirectory;
  final Future<IncomingShare?> Function(String) _readShare;
  Future<DeviceSnapshot> device(String id) async {
    if (id.isEmpty) {
      throw const RequestFailure('missing_device', '没有指定设备，请从设备列表重新打开。');
    }
    final device = await _readDevice(id);
    if (device.id != id) {
      throw const RequestFailure('missing_device', '设备记录已移除或无法读取，请返回设备列表重新选择。');
    }
    return device;
  }

  Future<FileTransferSnapshot> transfer(String id) async {
    final task = await _readTransfer(id);
    if (task.id != id) {
      throw const RequestFailure('missing_transfer', '传输记录已不存在，请在传输中心重新选择。');
    }
    return task;
  }

  Future<VideoSessionView> session(String deviceId, String id) async {
    final matches = (await _readSessions(deviceId)).where(
      (view) =>
          view.sessionId == id &&
          view.deviceId == deviceId &&
          view.session.status != VideoSessionStatus.stopped,
    );
    if (matches.isEmpty) {
      throw const RequestFailure(
        'missing_session',
        '这个控制会话已结束。请从设备工作台明确打开新的画面。',
      );
    }
    return matches.first;
  }

  Future<FileCatalogEntry> file(String deviceId, String path) async {
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw const RequestFailure('invalid_path', '文件位置无效，请从文件目录重新打开。');
    }
    final separator = path.lastIndexOf('/');
    final parent = separator <= 0 ? '/' : path.substring(0, separator);
    final directory = await _readDirectory((deviceId: deviceId, path: parent));
    if (directory.deviceId != deviceId ||
        directory.path != FilePaths.remote(parent)) {
      throw const RequestFailure('missing_file', '文件所属设备或目录无法核验，请返回目录刷新。');
    }
    final matches = directory.entries.where((file) => file.path == path);
    if (matches.isEmpty) {
      throw const RequestFailure('missing_file', '文件已移动、移除或无法读取，请返回目录刷新。');
    }
    return matches.first;
  }

  Future<IncomingShare> share(String id) async {
    final share = await _readShare(id);
    if (share == null || share.shareId != id) {
      throw const RequestFailure('missing_share', '这次分享已处理或不在本机队列中，请重新从系统分享。');
    }
    return share;
  }
}
