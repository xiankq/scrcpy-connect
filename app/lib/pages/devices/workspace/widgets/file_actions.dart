import 'package:scrcpy_connect/services/files/received_directory.dart';
import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/media_cache_blocker.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/services/files/system_file_share.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

Future<void> retrieveFile(
  BuildContext context,
  AppController controller,
  Json device,
  Json file, {
  bool share = false,
}) async {
  if (share && !supportsSystemFileShare) {
    feedback(context, '此系统不支持文件分享，请选择取回原文件并保存。');
    return;
  }
  if (!_connected(controller, device)) {
    feedback(context, '设备已断开，请重连后再取回原文件。');
    return;
  }
  if (!fileCanOpen(file)) {
    feedback(context, fileUnavailableReason(file));
    return;
  }
  String? directory;
  final privateCache = share || Platform.isAndroid || Platform.isIOS;
  if (!privateCache) {
    directory = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
  }
  if (!privateCache && directory == null) return;
  directory ??= (await receivedDirectory()).path;
  if (!context.mounted) return;
  if (!_connected(controller, device)) return;
  final result = await _pull(context, controller, {
    'deviceId': device['id'],
    'path': file['path'],
    'destination': p.join(directory, value(file, 'name')),
    'conflict': 'ask',
    'destinationScope': privateCache ? 'privateCache' : 'localPath',
  });
  if (result == null || !context.mounted) return;
  final transferId = value(result, 'transferId');
  if (privateCache && transferId.isNotEmpty) {
    ReceiveContentRoute(taskId: transferId, share: share).push<void>(context);
    return;
  }
  final local = value(result, 'localPath', value(result, 'path'));
  if (result['status'] == 'completed' && local.isNotEmpty) {
    feedback(context, privateCache ? '已取回本机暂存，尚未保存到系统位置' : '已保存至 $local');
  } else {
    feedback(
      context,
      share
          ? '正在取回原文件，完成后请从传输详情分享'
          : privateCache
          ? '正在取回本机暂存，完成后可保存到系统位置'
          : '已建立传输任务，请在传输中心查看实际结果',
    );
    TransferCenterRoute().push<void>(context);
  }
}

Future<void> retrieveSelection(
  BuildContext context,
  AppController controller,
  Json device,
  List<Json> files, {
  bool Function()? canSubmit,
  bool canReduceSelection = false,
}) async {
  if (files.isEmpty) return;
  bool ready() => _connected(controller, device) && (canSubmit?.call() ?? true);
  if (!ready()) return;
  if (files.any((file) => !fileCanOpen(file))) {
    feedback(context, '所选内容包含无法解析路径的文件，请重新选择可操作的文件。');
    return;
  }
  final privateCache = Platform.isAndroid || Platform.isIOS;
  final directory = privateCache
      ? (await receivedDirectory()).path
      : await FilePicker.getDirectoryPath(
          dialogTitle: '保存 ${files.length} 项原文件',
        );
  if (directory == null || !context.mounted) return;
  if (!ready()) return;
  final result = await _pull(context, controller, {
    'deviceId': device['id'],
    'items': [
      for (final file in files)
        {
          'path': file['path'],
          'destination': p.join(directory, value(file, 'name')),
        },
    ],
    'conflict': 'ask',
    'destinationScope': privateCache ? 'privateCache' : 'localPath',
  }, canReduceSelection: canReduceSelection);
  if (result != null && context.mounted) {
    TransferCenterRoute().push<void>(context);
  }
}

bool _connected(AppController controller, Json device) {
  final state = controller.snapshot();
  final current = state.devices
      .where((item) => item['id'] == device['id'])
      .firstOrNull;
  return current?['status'] == 'connected' && !state.reconciliationPending;
}

Future<Json?> _pull(
  BuildContext context,
  AppController controller,
  Json params, {
  bool canReduceSelection = false,
}) async {
  try {
    return await controller.request('files.pull', params);
  } catch (error) {
    if (context.mounted) {
      if (isMediaCacheAdmissionFailure(error)) {
        await showMediaCacheAdmissionFailure(
          context,
          controller,
          error,
          canReduceSelection: canReduceSelection,
          onOpenPhone: () =>
              openRemoteRoute(context, deviceId: value(params, 'deviceId')),
        );
      } else {
        feedback(context, '$error');
      }
    }
    return null;
  }
}
