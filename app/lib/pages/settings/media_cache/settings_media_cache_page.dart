import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class MediaCachePage extends HookWidget {
  const MediaCachePage({super.key, required this.controller});
  final AppStore controller;

  @override
  Widget build(BuildContext context) {
    final revision = useState(0);
    final busy = useState(false);
    final outcome = useState<String?>(null);
    return PageFrame(
      title: '媒体暂存',
      actions: [
        GlassActionIcon(
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
          final protectedItems = objects(data['protectedItems']);
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
                      Text(
                        data['spaceVerified'] == false
                            ? '当前可用空间待核验'
                            : '本次可用 ${_size(bytes('availableBytes'))}',
                      ),
                      if (data['spaceVerified'] == false)
                        const StateNote('当前无法核验本机实际空间，新的原件准备暂时停止。'),
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
              SettingsGroup(
                children: [
                  ListTile(
                    leading: const ListIconBadge(
                      icon: LucideIcons.shieldCheck,
                      backgroundColor: DesignTokens.colorListIconMint,
                    ),
                    title: const Text('受保护'),

                    trailing: Text(_size(protected)),
                  ),
                  ListTile(
                    leading: const ListIconBadge(
                      icon: LucideIcons.brushCleaning,
                      backgroundColor: DesignTokens.colorListIconBlue,
                    ),
                    title: const Text('可回收'),

                    trailing: Text(_size(reclaimable)),
                  ),
                  if (reserved > 0)
                    ListTile(
                      leading: const ListIconBadge(
                        icon: LucideIcons.download,
                        backgroundColor: DesignTokens.colorListIconAmber,
                      ),
                      title: const Text('正在准备'),

                      trailing: Text(_size(reserved)),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              if (reclaimable == 0)
                const StateNote('当前没有可清理项目。受保护内容仍在使用或等待外部读取，保存到系统位置也不会自动解除保护。'),
              if (reclaimable > 0)
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
                              ApplicationCommand.mediaCacheClear,
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
              if (protectedItems.isNotEmpty) const SectionTitle('受保护原件'),
              for (final item in protectedItems)
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value(item, 'name', '暂存原件'),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      Text(
                        '${_cacheSourceLabel(controller, item)} · ${_size((item['bytes'] as num?)?.toInt() ?? 0)}',
                      ),
                      if (value(item, 'sourcePath').isNotEmpty)
                        Text(value(item, 'sourcePath')),
                      StateNote(value(item, 'reason', '正在使用，继续保留')),
                      Wrap(
                        spacing: DesignTokens.spacingSm,
                        children: [
                          if (value(item, 'transferId').isNotEmpty)
                            TextButton(
                              onPressed: () => TransferDetailsRoute(
                                taskId: value(item, 'transferId'),
                              ).push<void>(context),
                              child: const Text('查看传输'),
                            ),
                          if (supportsSystemDocumentSave &&
                              item['canExport'] == true &&
                              value(item, 'transferId').isNotEmpty)
                            TextButton(
                              onPressed: () => DocumentExportRoute(
                                taskId: value(item, 'transferId'),
                              ).push<void>(context),
                              child: const Text('保存到系统位置'),
                            ),
                          if (supportsSystemFileShare &&
                              item['canShare'] == true)
                            TextButton(
                              onPressed: busy.value
                                  ? null
                                  : () async {
                                      busy.value = true;
                                      try {
                                        final result = await sharePreparedFile(
                                          context,
                                          controller,
                                          value(item, 'localPath'),
                                        );
                                        if (context.mounted) {
                                          feedback(context, result);
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          feedback(context, '系统分享未确认完成：$error');
                                        }
                                      } finally {
                                        if (context.mounted) busy.value = false;
                                      }
                                    },
                              child: const Text('系统分享'),
                            ),
                        ],
                      ),
                    ],
                  ),
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

String _cacheSourceLabel(AppStore controller, Json item) {
  final source = value(item, 'sourceLabel', '来源暂不可核验');
  final device = controller
      .snapshot()
      .devices
      .where((device) => device['id'] == source)
      .firstOrNull;
  return device == null ? source : deviceName(device);
}
