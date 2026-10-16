import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool fileCanOpen(Json file) =>
    file['path'] is String &&
    value(file, 'path').isNotEmpty &&
    file['canOpen'] != false;
bool fileCanManage(Json file) =>
    file['path'] is String &&
    value(file, 'path').isNotEmpty &&
    file['canManage'] != false;
String fileUnavailableReason(Json file) =>
    value(file, 'reason', '文件名无法解析为有效路径，暂时无法操作。');

Future<void> retrieveFile(
  BuildContext context,
  AppController controller,
  Json device,
  Json file, {
  bool share = false,
}) async {
  if (!fileCanOpen(file)) {
    feedback(context, fileUnavailableReason(file));
    return;
  }
  String? directory;
  final privateCache = share || Platform.isAndroid;
  if (!privateCache) {
    directory = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
  }
  if (!privateCache && directory == null) return;
  directory ??= (await receivedDirectory()).path;
  if (!context.mounted) return;
  final result = await perform(context, controller, 'files.pull', {
    'deviceId': device['id'],
    'path': file['path'],
    'destination': '$directory/${value(file, 'name')}',
    'conflict': 'ask',
    'destinationScope': privateCache ? 'privateCache' : 'localPath',
  });
  if (result == null || !context.mounted) return;
  final local = value(result, 'localPath', value(result, 'path'));
  if (share && local.isNotEmpty && result['status'] == 'completed') {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(local)]));
    } catch (e) {
      if (context.mounted) feedback(context, '无法交给系统分享：$e');
    }
  } else if (result['status'] == 'completed' && local.isNotEmpty) {
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
  List<Json> files,
) async {
  if (files.isEmpty) return;
  if (files.any((file) => !fileCanOpen(file))) {
    feedback(context, '所选内容包含无法解析路径的文件，请重新选择可操作的文件。');
    return;
  }
  final privateCache = Platform.isAndroid;
  final directory = privateCache
      ? (await receivedDirectory()).path
      : await FilePicker.getDirectoryPath(
          dialogTitle: '保存 ${files.length} 项原文件',
        );
  if (directory == null || !context.mounted) return;
  final result = await perform(context, controller, 'files.pull', {
    'deviceId': device['id'],
    'items': [
      for (final file in files)
        {
          'path': file['path'],
          'destination': '$directory/${value(file, 'name')}',
        },
    ],
    'conflict': 'ask',
    'destinationScope': privateCache ? 'privateCache' : 'localPath',
  });
  if (result != null && context.mounted) {
    TransferCenterRoute().push<void>(context);
  }
}

/// Outgoing user files are isolated from private identity and app state. The
/// native FileProvider exposes this subtree, never the whole temporary root.
Future<Directory> receivedDirectory() async {
  final cache = await getTemporaryDirectory();
  final outgoing = await Directory('${cache.path}/outgoing')
      .create(recursive: true);
  return outgoing.createTemp('received-');
}
