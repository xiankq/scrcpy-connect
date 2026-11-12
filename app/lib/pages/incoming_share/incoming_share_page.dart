import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';

import 'widgets/share_device_card.dart';

import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class IncomingSharePage extends HookConsumerWidget {
  const IncomingSharePage({
    super.key,
    required this.controller,
    required this.share,
  });
  final AppNotifier controller;
  final IncomingShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share =
        ref.watch(
          appProvider.select(
            (state) => state.pendingShares
                .where((item) => item.shareId == this.share.shareId)
                .firstOrNull,
          ),
        ) ??
        this.share;
    final appDevices = ref.watch(
      deviceListProvider.select((state) => state.devices),
    );
    final files = share.files;
    final text = share.text;
    final importing = [
      IncomingShareStatus.starting,
      IncomingShareStatus.importing,
    ].contains(share.status);
    final deviceId = useState<String?>(null);
    final path = useTextEditingController(text: '/sdcard/Download');
    useListenable(path);
    final includeFiles = useState(true);
    final includeText = useState(text.isNotEmpty);
    final busy = useState(false);
    final pushed = useState(false);
    final copied = useState(false);
    final finished = useState(false);
    final error = useState<String?>(null);
    final locked = pushed.value || copied.value;
    final devices = appDevices
        .where((d) => d.status == DeviceConnectionStatus.connected)
        .toList();
    final selected = devices.where((d) => d.id == deviceId.value).firstOrNull;
    final needsPush = includeFiles.value && files.isNotEmpty && !pushed.value;
    final needsCopy = includeText.value && !copied.value;
    final canSubmit =
        !busy.value &&
        !importing &&
        (selected != null || (!needsPush && !needsCopy)) &&
        ((includeFiles.value && files.isNotEmpty) || includeText.value) &&
        (!needsPush ||
            (path.text.startsWith('/') && !path.text.contains('\u0000')));

    Future<void> finish({bool showTransfers = false}) async {
      await controller.shareInbox.consume(share.shareId);
      if (!context.mounted) return;
      finished.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        closePage<void>(context);
        if (showTransfers && context.mounted) {
          const TransferCenterRoute().push<void>(context);
        }
      });
    }

    Future<void> cancel() async {
      if (busy.value) return;
      busy.value = true;
      try {
        await finish();
      } catch (e) {
        if (context.mounted) error.value = '暂时无法关闭本次分享：$e';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> submit() async {
      if (!canSubmit) return;
      // 任何异步请求前先固定用户确认的目标。
      final target = deviceId.value;
      final directory = path.text.trim().replaceFirst(RegExp(r'/+$'), '');
      busy.value = true;
      error.value = null;
      try {
        if (needsPush) {
          if (target == null) {
            throw const RequestFailure('missing_device', '请先选择目标设备。');
          }
          await controller.directories.readDirectory((
            deviceId: target,
            path: directory.isEmpty ? '/' : directory,
          ));
          await controller.fileTransfers.startTransfer(
            FileTransferPlan(
              deviceId: target,
              direction: .push,
              items: [
                for (final file in files)
                  FileTransferSelection(
                    source: file.localPath,
                    destination: '$directory/${file.name}',
                  ),
              ],
            ),
            shareId: share.shareId,
          );
          if (!context.mounted) return;
          pushed.value = true;
        }
        if (needsCopy) {
          await controller.clipboard.writeClipboard(
            ClipboardTarget.device(deviceId: target!),
            text,
          );
          if (!context.mounted) return;
          copied.value = true;
        }
        await finish(showTransfers: pushed.value);
      } catch (e) {
        if (context.mounted) error.value = '$e';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final errors = share.errors;
    final leading = <Widget>[
      const StateNote('选择设备后确认保存目录；提交时固定来源和目标，切换页面不改目标。'),
      if (importing) ...[
        const ContentLoadingIndicator(),
        const StateNote('正在读取分享内容，完成后即可发送。你也可以取消本次分享。'),
      ],
    ];
    final fileHeader = <Widget>[
      if (files.isNotEmpty)
        ConnectSwitchRow(
          title: Text('传入 ${files.length} 个文件'),
          value: includeFiles.value,
          onChanged: busy.value || locked
              ? null
              : (v) => includeFiles.value = v,
        ),
    ];
    final middle = <Widget>[
      if (text.isNotEmpty) ...[
        ConnectSwitchRow(
          title: const Text('写入设备剪贴板'),

          value: includeText.value,
          onChanged: busy.value || locked ? null : (v) => includeText.value = v,
        ),
        ContentPanel(child: SelectableText(text)),
        const SizedBox(height: DesignTokens.spacingMd),
      ],
      const SectionTitle('接收设备'),
      if (devices.isEmpty)
        const StateNote('当前没有已连接设备。先恢复设备连接，再返回这里选择；也可以取消本次分享。'),
    ];
    final trailing = <Widget>[
      if (includeFiles.value && files.isNotEmpty) ...[
        const SectionTitle('目标目录'),
        TextField(
          controller: path,
          enabled: !busy.value && !locked,
          decoration: const InputDecoration(
            labelText: '设备上的完整目录',
            helperText: '同名文件会在传输中心等待你确认',
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        OutlinedButton.icon(
          onPressed: selected == null || busy.value || locked
              ? null
              : () async {
                  final directory = await ShareDirectoryRoute(
                    deviceId: selected.id,
                    path: path.text,
                  ).push<String>(context);
                  if (directory != null && context.mounted) {
                    path.text = directory;
                  }
                },
          icon: const Icon(
            LucideIcons.folderOpen,
            size: DesignTokens.componentIconActionSize,
          ),
          label: const Text('浏览设备目录'),
        ),
      ],
      if (selected != null)
        StateNote(
          '本次目标：${deviceName(selected)}${includeFiles.value ? ' · ${path.text}' : ' · 剪贴板'}',
        ),
      if (pushed.value) const StateNote('文件任务已提交；再次确认不会重复提交这批文件。'),
      if (copied.value) const StateNote('文字已写入指定设备剪贴板。'),
      if (error.value != null)
        StateNote(error.value!, icon: LucideIcons.circleAlert),
      const SizedBox(height: DesignTokens.spacingMd),
      FilledButton(
        onPressed: canSubmit ? submit : null,
        child: Text(
          busy.value
              ? '正在提交…'
              : locked
              ? '继续完成'
              : '确认提交',
        ),
      ),
      if (busy.value)
        const Padding(
          padding: EdgeInsets.all(DesignTokens.spacingMd),
          child: ContentLoadingIndicator(),
        ),
    ];
    final errorsStart = leading.length;
    final fileHeaderStart = errorsStart + errors.length;
    final filesStart = fileHeaderStart + fileHeader.length;
    final middleStart = filesStart + files.length;
    final devicesStart = middleStart + middle.length;
    final trailingStart = devicesStart + devices.length;
    final indices = <Key, int>{
      for (var index = 0; index < errors.length; index++)
        ValueKey(('incoming-error', index)): errorsStart + index,
      for (var index = 0; index < files.length; index++)
        ValueKey(('incoming-file', share.shareId, index)): filesStart + index,
      for (var index = 0; index < devices.length; index++)
        ValueKey(('incoming-device', devices[index].id)): devicesStart + index,
    };

    return PopScope(
      canPop: finished.value,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) cancel();
      },
      child: PageFrame(
        title: '发送到设备',

        trailingAction: TextButton(
          onPressed: busy.value ? null : cancel,
          child: Text(locked ? '关闭' : '取消'),
        ),
        child: GroupedListView.builder(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          itemCount: trailingStart + trailing.length,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) {
            if (index < errorsStart) return leading[index];
            if (index < fileHeaderStart) {
              final row = index - errorsStart;
              return StateNote(
                errors[row],
                key: ValueKey(('incoming-error', row)),
                icon: LucideIcons.circleAlert,
              );
            }
            if (index < filesStart) return fileHeader[index - fileHeaderStart];
            if (index < middleStart) {
              final row = index - filesStart;
              return ActionRow(
                key: ValueKey(('incoming-file', share.shareId, row)),
                icon: LucideIcons.file,
                title: files[row].name,
              );
            }
            if (index < devicesStart) return middle[index - middleStart];
            if (index >= trailingStart) return trailing[index - trailingStart];
            final device = devices[index - devicesStart];
            return ShareDeviceCard(
              key: ValueKey(('incoming-device', device.id)),
              device: device,
              selected: deviceId.value == device.id,
              onTap: busy.value || locked
                  ? null
                  : () => deviceId.value = device.id,
            );
          },
        ),
      ),
    );
  }
}
