import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class IncomingSharePage extends HookConsumerWidget {
  const IncomingSharePage({
    super.key,
    required this.controller,
    required this.share,
  });
  final AppController controller;
  final Json share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share =
        ref.watch(
          appControllerProvider.select(
            (state) => state.pendingShares
                .where((item) => item['shareId'] == this.share['shareId'])
                .firstOrNull,
          ),
        ) ??
        this.share;
    final appDevices = ref.watch(
      appControllerProvider.select((state) => state.devices),
    );
    final files = objects(share['files']);
    final text = value(share, 'text');
    final importing = ['starting', 'importing'].contains(share['status']);
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
        .where((d) => d['status'] == 'connected')
        .toList();
    final selected = devices
        .where((d) => d['id'] == deviceId.value)
        .firstOrNull;
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
      await controller.consumeShare(value(share, 'shareId'));
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
      // Capture the confirmed target before any asynchronous request.
      final target = deviceId.value;
      final directory = path.text.trim().replaceFirst(RegExp(r'/+$'), '');
      busy.value = true;
      error.value = null;
      try {
        if (needsPush) {
          await controller.execute(InteropCommand.filesList, {
            'deviceId': target,
            'path': directory.isEmpty ? '/' : directory,
          });
          await controller.execute(InteropCommand.filesPush, {
            'shareId': share['shareId'],
            'deviceId': target,
            'items': [
              for (final file in files)
                {
                  'source': file['localPath'],
                  'destination': '$directory/${value(file, 'name')}',
                },
            ],
            'conflict': 'ask',
          });
          if (!context.mounted) return;
          pushed.value = true;
        }
        if (needsCopy) {
          final result = await controller.execute(InteropCommand.clipboardSet, {
            'deviceId': target,
            'text': text,
          });
          if (!context.mounted) return;
          if (result['applied'] != true) {
            throw RequestFailure(
              'clipboard_unconfirmed',
              value(
                result,
                'reason',
                value(
                  result,
                  'message',
                  '手机尚未确认剪贴板写入，分享内容已保留。请在手机核对后再决定是否重新提交。',
                ),
              ),
            );
          }
          copied.value = true;
        }
        await finish(showTransfers: pushed.value);
      } catch (e) {
        if (context.mounted) error.value = '$e';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

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
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            const StateNote('明确选择本次接收设备。切换当前操作设备不会改变已提交任务的目标。'),
            if (importing) ...[
              const LinearProgressIndicator(),
              const StateNote('正在读取分享内容，完成后即可发送。你也可以取消本次分享。'),
            ],
            for (final message in strings(share['errors']))
              StateNote(message, icon: LucideIcons.circleAlert),
            if (files.isNotEmpty) ...[
              ConnectSwitchRow(
                title: Text('传入 ${files.length} 个文件'),
                value: includeFiles.value,
                onChanged: busy.value || locked
                    ? null
                    : (v) => includeFiles.value = v,
              ),
              for (final file in files)
                ActionRow(icon: LucideIcons.file, title: value(file, 'name')),
            ],
            if (text.isNotEmpty) ...[
              ConnectSwitchRow(
                title: const Text('写入设备剪贴板'),

                value: includeText.value,
                onChanged: busy.value || locked
                    ? null
                    : (v) => includeText.value = v,
              ),
              ContentPanel(child: SelectableText(text)),
              const SizedBox(height: DesignTokens.spacingMd),
            ],
            const SectionTitle('接收设备'),
            if (devices.isEmpty)
              const StateNote('当前没有已连接设备。先恢复设备连接，再返回这里选择；也可以取消本次分享。'),
            for (final device in devices)
              ChoiceRow<String>(
                value: value(device, 'id'),
                groupValue: deviceId.value,
                onChanged: busy.value || locked
                    ? null
                    : (v) => deviceId.value = v,
                title: Text(deviceName(device)),
              ),
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
                          deviceId: value(selected, 'id'),
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
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
