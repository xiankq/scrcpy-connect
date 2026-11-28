import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/document_operation_notifier.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/hooks/use_document_picker.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DocumentImportPage extends HookConsumerWidget {
  const DocumentImportPage({
    super.key,
    required this.device,
    required this.destination,
    required this.onSubmitted,
  });
  final DeviceSnapshot device;
  final String destination;
  final VoidCallback onSubmitted;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(fileTransfersProvider);
    final scope = useMemoized(Object.new);
    final provider = documentOperationProvider(scope: scope);
    final operation = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final currentOperation = actions.captureScope();
    useDocumentPicker(ref, actions);
    final reviewed = useValueNotifier(false, [operation.result, transfers]);
    useValueListenable(reviewed);
    final sending = useValueNotifier(false, [operation.result, transfers]);
    useValueListenable(sending);
    bool ownsScope() =>
        context.mounted &&
        currentOperation() &&
        identical(ref.read(fileTransfersProvider), transfers);
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final note = type.footnote.copyWith(color: colors.textSecondary);
    final leading = <Widget>[
      Row(
        children: [
          Icon(
            LucideIcons.smartphone,
            size: _deviceGlyphSize,
            color: colors.textSecondary,
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(child: Text(deviceName(device), style: note)),
        ],
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      ContentPanel(
        padding: const EdgeInsets.all(DesignTokens.spacingXxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: FeatureIcon(
                LucideIcons.folderUp,
                color: folderKindColor,
                size: FeatureIcon.detailSize,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            Text(
              result == null ? '准备发送一个文件夹' : '已读取的文件夹',
              textAlign: TextAlign.center,
              style: type.title3,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              result == null
                  ? '先选择本机文件夹。开始前会读取并列出文件、子文件夹和无法发送的项目。'
                  : '核对实际文件、子文件夹和无法读取的项目后，再发送到手机。',
              textAlign: TextAlign.center,
              style: type.subheadline.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            Center(
              child: AppButton(
                label: result == null ? '选择文件夹' : '重新选择文件夹',
                icon: LucideIcons.folderOpen,
                role: usable ? AppButtonRole.secondary : AppButtonRole.primary,
                onPressed: operation.busy || sending.value
                    ? null
                    : () {
                        reviewed.value = false;
                        actions.importDirectory();
                      },
              ),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              '保留目录结构与空文件夹；符号链接不会跟随。',
              textAlign: TextAlign.center,
              style: note,
            ),
          ],
        ),
      ),
      const SectionTitle('发送到'),
      SettingsGroup(
        children: [
          AppListRow(
            leading: const ListIconBadge(
              icon: folderKindIcon,
              backgroundColor: folderKindColor,
            ),
            title: Text(destinationLabel),
            subtitle: Tooltip(
              message: destination,
              child: Text(destinationScope),
            ),
          ),
        ],
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      if (operation.busy) ...[
        const ContentLoadingIndicator(),
        const StateNote('正在等待系统选择或读取实际内容…'),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: operation.cancelling ? '正在取消…' : '取消本次读取',
            role: AppButtonRole.text,
            size: AppButtonSize.section,
            onPressed: operation.cancelling ? null : actions.cancel,
          ),
        ),
      ],
      if (operation.error != null)
        StateNote(
          operation.error!,
          icon: LucideIcons.circleAlert,
          color: colors.error,
        ),
      if (result != null)
        ContentPanel(
          child: DefaultTextStyle.merge(
            style: type.subheadline,
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
                  style: type.headline,
                ),
                const SizedBox(height: DesignTokens.spacingXs),
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
        ),
    ];
    final trailing = <Widget>[
      if (partial && usable)
        CheckboxListTile(
          value: reviewed.value,
          onChanged: sending.value ? null : (v) => reviewed.value = v ?? false,
          title: const Text('我已核对，只发送已取回的内容'),
        ),
    ];
    return PageFrame(
      bottom: usable
          ? AppButton(
              label: sending.value
                  ? '正在建立传输…'
                  : partial
                  ? '发送已核对的内容'
                  : '发送此文件夹',
              role: AppButtonRole.primary,
              expand: true,
              onPressed: sending.value || partial && !reviewed.value
                  ? null
                  : () async {
                      if (!await confirm(
                            context,
                            '发送此文件夹？',
                            '将“$name”发送到 ${deviceName(device)} 的 $target。同名内容逐项确认，不会自动覆盖。',
                            action: '确认发送',
                          ) ||
                          (!context.mounted || !ownsScope())) {
                        return;
                      }
                      sending.value = true;
                      final response = await performAction(
                        context,
                        () => transfers.startTransfer(
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
                      if (context.mounted && ownsScope()) {
                        sending.value = false;
                        if (response != null) onSubmitted();
                      }
                    },
            )
          : null,
      title: '发送到手机',
      child: GroupedListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentPagePadding,
        ),
        itemCount: leading.length + errors.length + trailing.length,
        itemBuilder: (context, index) {
          if (index < leading.length) return leading[index];
          final errorIndex = index - leading.length;
          if (errorIndex < errors.length) {
            final error = errors[errorIndex];
            return StateNote(
              '${error.path.isEmpty ? '' : '${error.path}\n'}${failureCodeMessage(error.code, fallback: '系统无法读取此项。请重新选择文件。')}',
              icon: LucideIcons.circleAlert,
              color: colors.error,
            );
          }
          return trailing[errorIndex - errors.length];
        },
      ),
    );
  }
}

/// 设备来源行的图形大小（与 footnote 行高对齐）。
const _deviceGlyphSize = DesignTokens.componentChevronSize;
