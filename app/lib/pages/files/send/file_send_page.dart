import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/pages/files/file_actions_notifier.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/document_picker.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class FileSendPage extends HookConsumerWidget {
  const FileSendPage({
    super.key,
    required this.device,
    required this.initialPath,
  });
  final DeviceSnapshot device;
  final String initialPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = useState(initialPath);
    final picked =
        useState<List<({String path, String name, int? size, bool directory})>>(
          [],
        );
    final picking = useState(false);
    final scope = useMemoized(Object.new);
    final target = (deviceId: device.id, path: destination.value);
    final directory = ref.watch(fileDirectoryProvider(target));
    final provider = fileActionsProvider(target, scope: scope);
    final operation = ref.watch(provider);
    final selection = picked.value;
    final label = deviceName(device);
    final colors = AppColors.of(context);
    final note = AppTypography.of(context).footnote
        .copyWith(color: colors.textSecondary);

    Future<void> choose({required bool directory}) async {
      if (picking.value) return;
      if (directory && Platform.isAndroid) {
        await DocumentImportRoute(
          deviceId: device.id,
          destination: destination.value,
        ).push<bool>(context);
        return;
      }
      picking.value = true;
      try {
        if (directory) {
          final result = await DocumentPicker.pickLocalDirectory(
            dialogTitle: '选择发送的文件夹',
          );
          if (result == null || !context.mounted) return;
          final name = p.basename(p.normalize(result));
          if (name.isEmpty ||
              name == '.' ||
              p.equals(p.normalize(result), p.rootPrefix(result))) {
            feedback(context, '请选择一个有名称的文件夹。');
            return;
          }
          picked.value = [
            (path: result, name: name, size: null, directory: true),
          ];
        } else {
          final files = await FilePicker.pickFiles();
          if (files.isEmpty || !context.mounted) return;
          final entries = await Future.wait([
            for (final file in files)
              if (file.path case final path?)
                file.length().then(
                  (size) => (
                    path: path,
                    name: file.name,
                    size: size,
                    directory: false,
                  ),
                ),
          ]);
          if (!context.mounted) return;
          if (entries.isEmpty) {
            feedback(context, '无法读取所选文件。请在系统文件选择器中重新选择。');
          } else {
            picked.value = entries;
            if (entries.length < files.length) {
              feedback(context, '部分所选文件无法读取，确认页仅显示可发送的文件。');
            }
          }
        }
      } finally {
        if (context.mounted) picking.value = false;
      }
    }

    final hasSelection = selection.isNotEmpty;
    final isDirectory = selection.firstOrNull?.directory == true;
    return PopScope(
      canPop: !hasSelection,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && !operation.busy && !picking.value) picked.value = [];
      },
      child: PageFrame(
        onBack: !hasSelection
            ? null
            : () {
                if (!operation.busy && !picking.value) picked.value = [];
              },
        title: !hasSelection ? '发送到手机' : '确认发送',
        bottom: !hasSelection
            ? null
            : AppButton(
                label: operation.busy
                    ? '正在建立传输…'
                    : isDirectory
                    ? '发送此文件夹'
                    : '发送 ${selection.length} 个文件',
                role: AppButtonRole.primary,
                expand: true,
                onPressed:
                    !directory.verified || operation.busy || picking.value
                    ? null
                    : () async {
                        final sent = await ref.read(provider.notifier).send([
                          for (final entry in selection)
                            FileTransferSelection(
                              source: entry.path,
                              destination: p.posix.join(
                                destination.value,
                                entry.name,
                              ),
                            ),
                        ]);
                        if (!context.mounted || !sent) return;
                        closePage<bool>(context, true);
                      },
              ),
        child: GroupedListView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentPagePadding,
          ),
          children: [
            SettingsGroup(
              children: [
                if (!hasSelection) ...[
                  ActionRow(
                    icon: LucideIcons.fileText,
                    color: FunctionTone.file,
                    title: '选择文件',
                    onTap: picking.value
                        ? null
                        : () => choose(directory: false),
                  ),
                  if (Platform.isAndroid || Platform.isLinux)
                    ActionRow(
                      icon: LucideIcons.folder,
                      color: FunctionTone.file,
                      title: '选择文件夹',
                      onTap: picking.value
                          ? null
                          : () => choose(directory: true),
                    ),
                ] else ...[
                  for (final entry in selection)
                    ActionRow(
                      icon: entry.directory
                          ? LucideIcons.folder
                          : fileKindIcon(FileKind.classify(name: entry.name)),
                      color: entry.directory
                          ? folderKindColor
                          : fileKindColor(
                              FileKind.classify(name: entry.name),
                              name: entry.name,
                            ),
                      title: entry.name,
                      value: entry.size == null
                          ? null
                          : fileSizeLabel(entry.size),
                      onTap: picking.value || operation.busy
                          ? null
                          : () => choose(directory: isDirectory),
                    ),
                  ActionRow(
                    icon: LucideIcons.smartphone,
                    color: FunctionTone.device,
                    title: '目标设备',
                    value: label,
                  ),
                  ActionRow(
                    icon: LucideIcons.folder,
                    color: FunctionTone.file,
                    title: '目标目录',
                    value: destination.value,
                    onTap: operation.busy
                        ? null
                        : () async {
                            final next = await ShareDirectoryRoute(
                              deviceId: device.id,
                              path: destination.value,
                            ).push<String>(context);
                            if (context.mounted && next != null) {
                              destination.value = next;
                            }
                          },
                  ),
                ],
              ],
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            ContentPanel(
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.monitor,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.textSecondary,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingSm,
                          ),
                          child: SizedBox(
                            height: DesignTokens.componentSeparatorHeight,
                            child: ColoredBox(color: colors.separator),
                          ),
                        ),
                      ),
                      Icon(
                        LucideIcons.smartphone,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          !hasSelection
                              ? '本机内容'
                              : selection.length == 1
                              ? selection.single.name
                              : '${selection.length} 个文件',
                          style: note,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingSm),
                      Expanded(
                        child: Text(
                          !hasSelection
                              ? label
                              : fileDirectoryLabel(destination.value),
                          textAlign: TextAlign.end,
                          style: note,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hasSelection && directory.error != null)
              StateNote('无法确认目标目录。请刷新或选择其他目录。'),
            if (hasSelection && directory.error != null)
              AppButton(
                label: '刷新目标目录',
                role: AppButtonRole.secondaryOnPage,
                onPressed: () =>
                    ref.read(fileDirectoryProvider(target).notifier).refresh(),
              ),
            if (operation.error case final message?) StateNote(message),
          ],
        ),
      ),
    );
  }
}
