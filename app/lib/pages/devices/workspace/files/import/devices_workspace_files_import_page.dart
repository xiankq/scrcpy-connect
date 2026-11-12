import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/documents/document_operation.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DocumentImportPage extends HookWidget {
  const DocumentImportPage({
    super.key,
    required this.controller,
    required this.device,
    required this.destination,
    required this.onSubmitted,
  });
  final AppNotifier controller;
  final DeviceSnapshot device;
  final String destination;
  final VoidCallback onSubmitted;
  @override
  Widget build(BuildContext context) {
    final operation = useDocumentOperationController(controller);
    final reviewed = useState(false);
    final sending = useState(false);
    final result = operation.result;
    final partial = result?.status == DocumentOutcomeStatus.partial;
    final imported = [
      DocumentOutcomeStatus.imported,
      DocumentOutcomeStatus.partial,
    ].contains(result?.status);
    final name = result?.name ?? '';
    final safeName =
        name.isNotEmpty &&
        !name.contains('/') &&
        name != '.' &&
        name != '..' &&
        !name.contains('\u0000');
    final usable =
        imported &&
        safeName &&
        (result?.localPath ?? '').isNotEmpty &&
        ((result?.files ?? 0) + (result?.directories ?? 0) > 0);
    final target =
        '${destination.endsWith('/') ? destination.substring(0, destination.length - 1) : destination}/$name';
    final errors = result?.errors ?? <DocumentIssue>[];
    final destinationLabel = fileDirectoryLabel(destination);
    final destinationScope =
        destination == '/sdcard' || destination.startsWith('/sdcard/')
        ? '内部存储'
        : destination;
    final leading = <Widget>[
      SizedBox(
        height: DesignTokens.spacingLg,
        child: Row(
          children: [
            Icon(
              LucideIcons.smartphone,
              size: DesignTokens.componentIconSmallSize - 2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: DesignTokens.spacingTight),
            Expanded(
              child: Text(
                deviceName(device),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      ContentPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: DesignTokens.componentEmptyContentIconSize,
                height: DesignTokens.componentEmptyContentIconSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? DesignTokens.colorAccentAmberSoftDark
                      : DesignTokens.colorAccentAmberSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.folderUp,
                  size: DesignTokens.componentIconLargeSize,
                  color: DesignTokens.colorAccentAmber,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              result == null ? '准备发送一个文件夹' : '已读取的文件夹',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            Text(
              result == null
                  ? '先选择本机文件夹。开始前会读取并列出文件、子文件夹和无法发送的项目。'
                  : '核对实际文件、子文件夹和无法读取的项目后，再发送到手机。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton.icon(
              onPressed: operation.busy || sending.value
                  ? null
                  : () {
                      reviewed.value = false;
                      operation.importDirectory();
                    },
              icon: const Icon(LucideIcons.folderOpen),
              label: Text(result == null ? '选择文件夹' : '重新选择文件夹'),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              '保留目录结构与空文件夹；符号链接不会跟随。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: DesignTokens.spacingLg),
      Text('发送到', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: DesignTokens.spacingXs),
      Container(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentRowLargeHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        ),
        child: Row(
          children: [
            const ListIconBadge(
              icon: LucideIcons.folder,
              backgroundColor: DesignTokens.colorListIconAmber,
            ),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destinationLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: DesignTokens.spacingXxs),
                  GlassTooltip(
                    message: destination,
                    child: Text(
                      destinationScope,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      if (operation.busy) ...[
        const ContentLoadingIndicator(),
        const StateNote('正在等待系统选择或读取实际内容…'),
        TextButton(
          onPressed: operation.cancelling ? null : operation.cancel,
          child: Text(operation.cancelling ? '正在取消…' : '取消本次读取'),
        ),
      ],
      if (operation.error != null)
        StateNote(operation.error!, icon: LucideIcons.circleAlert),
      if (result != null)
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partial
                    ? '部分内容已取回，请先核对'
                    : result.status == DocumentOutcomeStatus.imported
                    ? '已取回本机暂存，尚未发送'
                    : result.status == DocumentOutcomeStatus.cancelled
                    ? '本次选择已取消'
                    : '尚未取得可发送内容',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (name.isNotEmpty) Text(name),
              if (result.files != null && result.directories != null)
                Text(
                  '${result.files} 个文件 · ${result.directories} 个文件夹 · ${bytes(result.bytes)}',
                ),
              if ((result.skipped ?? 0) > 0) Text('跳过 ${result.skipped} 项'),
              if (usable) Text('发送位置：$target'),
              if (imported && !usable)
                const StateNote('系统未提供有效的文件夹名称、路径或可发送内容，请重新选择。'),
            ],
          ),
        ),
    ];
    final trailing = <Widget>[
      if (partial && usable)
        CheckboxListTile(
          value: reviewed.value,
          onChanged: sending.value ? null : (v) => reviewed.value = v ?? false,
          title: const Text('我已核对，只发送已取回的内容'),
        ),
      if (usable)
        FilledButton(
          onPressed: sending.value || partial && !reviewed.value
              ? null
              : () async {
                  if (!await confirm(
                        context,
                        '发送此文件夹？',
                        '将“$name”发送到 ${deviceName(device)} 的 $target。同名内容逐项确认，不会自动覆盖。',
                        action: '确认发送',
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  sending.value = true;
                  final response = await performAction(
                    context,
                    () => controller.fileTransfers.startTransfer(
                      FileTransferPlan(
                        deviceId: device.id,
                        direction: .push,
                        items: [
                          FileTransferSelection(
                            source: result!.localPath!,
                            destination: target,
                          ),
                        ],
                      ),
                      shareId: result.managedSourceId,
                    ),
                  );
                  if (context.mounted) {
                    sending.value = false;
                    if (response != null) onSubmitted();
                  }
                },
          child: Text(
            sending.value
                ? '正在建立传输…'
                : partial
                ? '发送已核对的内容'
                : '发送此文件夹',
          ),
        ),
    ];
    return PageFrame(
      title: '发送到手机',
      child: GroupedListView.builder(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: leading.length + errors.length + trailing.length,
        itemBuilder: (context, index) {
          if (index < leading.length) return leading[index];
          final errorIndex = index - leading.length;
          if (errorIndex < errors.length) {
            final error = errors[errorIndex];
            return StateNote(
              '${error.path}：${error.message.isEmpty ? '系统无法读取此项' : error.message}',
              icon: LucideIcons.circleAlert,
            );
          }
          return trailing[errorIndex - errors.length];
        },
      ),
    );
  }
}
