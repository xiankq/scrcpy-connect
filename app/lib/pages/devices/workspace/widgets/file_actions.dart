import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_local_directories.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/media_cache_blocker.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

Future<void> retrieveFile(
  BuildContext context,
  AppNotifier controller,
  DeviceSnapshot device,
  FileCatalogEntry file, {
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
  final result = await _pull(
    context,
    controller,
    FileTransferPlan(
      deviceId: device.id,
      direction: .pull,
      items: [
        FileTransferSelection(
          source: file.path!,
          destination: p.join(directory, file.name),
        ),
      ],
      destination: privateCache ? .privateCache : .localPath,
    ),
  );
  if (result == null || !context.mounted) return;
  final transferId = result.transferId;
  if (privateCache && transferId != null && transferId.isNotEmpty) {
    ReceiveContentRoute(taskId: transferId, share: share).push<void>(context);
    return;
  }
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

Future<void> retrieveSelection(
  BuildContext context,
  AppNotifier controller,
  DeviceSnapshot device,
  List<({String? path, String name, bool canOpen})> files, {
  bool Function()? canSubmit,
  bool canReduceSelection = false,
}) async {
  if (files.isEmpty) return;
  bool ready() => _connected(controller, device) && (canSubmit?.call() ?? true);
  if (!ready()) return;
  if (files.any((file) => !file.canOpen || file.path?.isNotEmpty != true)) {
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
  final result = await _pull(
    context,
    controller,
    FileTransferPlan(
      deviceId: device.id,
      direction: .pull,
      items: [
        for (final file in files)
          FileTransferSelection(
            source: file.path!,
            destination: p.join(directory, file.name),
          ),
      ],
      destination: privateCache ? .privateCache : .localPath,
    ),
    canReduceSelection: canReduceSelection,
  );
  if (result != null && context.mounted) {
    TransferCenterRoute().push<void>(context);
  }
}

bool _connected(AppNotifier controller, DeviceSnapshot device) {
  final state = controller.snapshot();
  final current = state.devices
      .where((item) => item.id == device.id)
      .firstOrNull;
  return current?.status == DeviceConnectionStatus.connected &&
      !state.reconciliationPending;
}

Future<FileTransferSubmission?> _pull(
  BuildContext context,
  AppNotifier controller,
  FileTransferPlan plan, {
  bool canReduceSelection = false,
}) async {
  try {
    return await controller.fileTransfers.startTransfer(plan);
  } catch (error) {
    if (context.mounted) {
      if (isMediaCacheAdmissionFailure(error)) {
        await showMediaCacheAdmissionFailure(
          context,
          controller,
          error,
          canReduceSelection: canReduceSelection,
          onOpenPhone: () => openRemoteRoute(context, deviceId: plan.deviceId),
        );
      } else {
        feedback(context, '$error');
      }
    }
    return null;
  }
}
