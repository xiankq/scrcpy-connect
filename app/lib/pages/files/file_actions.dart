import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_local_directories.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/media_cache_blocker.dart';

Future<void> retrieveFile(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
  FileCatalogEntry file, {
  bool share = false,
  bool openAfterTransfer = false,
}) async {
  final transfers = ref.read(fileTransfersProvider);
  final admission = ref.read(deviceReadinessProvider(device.id));
  bool current() =>
      context.mounted && identical(ref.read(fileTransfersProvider), transfers);
  bool ready() =>
      current() &&
      ref.read(deviceReadinessProvider(device.id)).ready &&
      ref.read(deviceReadinessProvider(device.id)) == admission;
  if (share && !supportsSystemFileShare) {
    feedback(context, '此系统不支持文件分享，请选择取回原文件并保存。');
    return;
  }
  if (!ready()) {
    feedback(context, '设备已断开，请重连后再取回原文件。');
    return;
  }
  if (!fileCanOpen(file)) {
    feedback(context, fileUnavailableReason(file));
    return;
  }
  String? directory;
  final privateCache =
      share || openAfterTransfer || Platform.isAndroid || Platform.isIOS;
  if (!privateCache) {
    directory = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
  }
  if (!privateCache && directory == null) return;
  directory ??= (await receivedDirectory()).path;
  if (!context.mounted) return;
  if (!ready()) return;
  final result = await _pull(
    context,
    transfers,
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
    current: current,
  );
  if (result == null || !context.mounted || !current()) return;
  final transferId = result.transferId;
  if (privateCache && transferId != null && transferId.isNotEmpty) {
    ReceiveContentRoute(
      taskId: transferId,
      share: share,
      $extra: openAfterTransfer ? true : null,
    ).push<void>(context);
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
  WidgetRef ref,
  DeviceSnapshot device,
  List<({String? path, String name, bool canOpen})> files, {
  bool Function()? canSubmit,
  bool canReduceSelection = false,
}) async {
  if (files.isEmpty) return;
  final transfers = ref.read(fileTransfersProvider);
  final admission = ref.read(deviceReadinessProvider(device.id));
  bool current() =>
      context.mounted && identical(ref.read(fileTransfersProvider), transfers);
  bool ready() =>
      current() &&
      ref.read(deviceReadinessProvider(device.id)).ready &&
      ref.read(deviceReadinessProvider(device.id)) == admission &&
      (canSubmit?.call() ?? true);
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
    transfers,
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
    current: current,
  );
  if (result != null && context.mounted && current()) {
    TransferCenterRoute().push<void>(context);
  }
}

Future<FileTransferSubmission?> _pull(
  BuildContext context,
  FileTransfers transfers,
  FileTransferPlan plan, {
  bool canReduceSelection = false,
  required bool Function() current,
}) async {
  try {
    return await transfers.startTransfer(plan);
  } catch (error) {
    if (context.mounted && current()) {
      if (isMediaCacheAdmissionFailure(error)) {
        await showMediaCacheAdmissionFailure(
          context,
          error,
          canReduceSelection: canReduceSelection,
          onOpenPhone: () {
            if (context.mounted && current()) {
              openRemoteRoute(context, deviceId: plan.deviceId);
            }
          },
        );
      } else {
        feedback(context, '$error');
      }
    }
    return null;
  }
}
