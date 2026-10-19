import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class MediaCachePage extends HookWidget {
  const MediaCachePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final revision = useState(0);
    final busy = useState(false);
    final outcome = useState<String?>(null);
    return PageFrame(
      title: '媒体暂存',
      actions: [
        IconButton(
          tooltip: '重新检查占用',
          onPressed: busy.value ? null : () => revision.value++,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: CommandView(
        controller: controller,
        command: 'media.cache.status',
        refreshKey: revision.value,
        emptyTitle: '暂时无法读取媒体暂存',
        builder: (context, data, _) {
          int bytes(String key) => (data[key] as num?)?.toInt() ?? 0;
          final used = bytes('usedBytes');
          final budget = bytes('budgetBytes');
          final protected = bytes('protectedBytes');
          final reclaimable = bytes('reclaimableBytes');
          final reserved = bytes('reservedBytes');
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              ContentPanel(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.hardDrive,
                        color: ConnectTokens.amber,
                      ),
                      const SizedBox(height: DesignTokens.spacingMd),
                      Text(
                        '已用 ${_size(used)}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text('暂存预算 ${_size(budget)}'),
                      const SizedBox(height: DesignTokens.spacingMd),
                      Semantics(
                        label: '暂存使用比例',
                        value: budget > 0
                            ? '${(used * 100 / budget).round()}%'
                            : '尚未设置',
                        child: LinearProgressIndicator(
                          value: budget > 0 ? (used / budget).clamp(0, 1) : 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('空间去向'),
              ListTile(
                leading: const Icon(LucideIcons.shieldCheck),
                title: const Text('受保护'),

                trailing: Text(_size(protected)),
              ),
              ListTile(
                leading: const Icon(LucideIcons.brushCleaning),
                title: const Text('可回收'),

                trailing: Text(_size(reclaimable)),
              ),
              if (reserved > 0)
                ListTile(
                  leading: const Icon(LucideIcons.download),
                  title: const Text('正在准备'),

                  trailing: Text(_size(reserved)),
                ),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: busy.value || reclaimable == 0
                    ? null
                    : () async {
                        if (!await confirm(
                              context,
                              '清理可回收暂存？',
                              '正在使用和已交给其他应用的内容会保留。下次查看已清理的内容时，将从手机重新获取。',
                              action: '清理暂存',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        busy.value = true;
                        try {
                          final result = await controller.execute(
                            InteropCommand.mediaCacheClear,
                          );
                          if (!context.mounted) return;
                          final deleted =
                              (result['deletedBytes'] as num?)?.toInt() ?? 0;
                          outcome.value = deleted == 0
                              ? '本次没有可回收内容，使用中的暂存已保留。'
                              : '已回收 ${_size(deleted)}，受保护内容已保留。';
                          revision.value++;
                        } catch (error) {
                          if (context.mounted) {
                            feedback(context, '清理未完成：$error');
                          }
                        } finally {
                          if (context.mounted) busy.value = false;
                        }
                      },
                icon: busy.value
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(LucideIcons.brushCleaning),
                label: Text(busy.value ? '正在清理' : '清理可回收暂存'),
              ),
              if (outcome.value != null) ...[
                const SizedBox(height: DesignTokens.spacingMd),
                StateNote(outcome.value!),
              ],
              const SizedBox(height: DesignTokens.spacingLg),
              const StateNote(
                '这里只管理互联媒体预览和接收原件的暂存，不会删除手机上的原件或你已保存的文件。\n\n交给其他应用的原件会继续保留，避免分享尚未读取完成时被清理。',
              ),
            ],
          );
        },
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
