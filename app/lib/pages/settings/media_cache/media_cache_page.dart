import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/content/cache_status_provider.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import '../widgets/settings_row.dart';

class MediaCachePage extends HookConsumerWidget {
  const MediaCachePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(contentCacheControlProvider);
    final devices = ref.watch(deviceListProvider).devices;
    bool ownsScope() =>
        context.mounted &&
        identical(ref.read(contentCacheControlProvider), cache);
    final query = ref.watch(cacheStatusProvider);
    final busy = useValueNotifier(false, [cache]);
    useValueListenable(busy);
    final outcome = useValueNotifier<String?>(null, [cache]);
    useValueListenable(outcome);
    final data = query.asData?.value;
    final reclaimable = data?.reclaimableBytes ?? 0;
    final protected = data?.protectedBytes ?? 0;
    Future<void> clear() async {
      if (!await confirm(
            context,
            '释放 ${_size(reclaimable)} 空间？',
            '使用中的 ${_size(protected)} 将继续保留。清理后再次查看时，将从手机重新获取。',
            action: '清理 ${_size(reclaimable)}',
          ) ||
          (!context.mounted || !ownsScope())) {
        return;
      }
      busy.value = true;
      try {
        final deleted = await cache.clear();
        if ((!context.mounted || !ownsScope())) return;
        outcome.value = deleted == 0
            ? '本次没有可回收内容，使用中的暂存已保留。'
            : '已回收 ${_size(deleted)}，受保护内容已保留。';
        ref.invalidate(cacheStatusProvider);
      } catch (error) {
        if (context.mounted && ownsScope()) {
          feedback(
            context,
            failureMessage(error, fallback: '无法清理媒体暂存。请关闭正在使用的文件后再试。'),
          );
        }
      } finally {
        if (context.mounted && ownsScope()) {
          busy.value = false;
        }
      }
    }

    return PageFrame(
      title: '媒体暂存',
      bottom: data == null
          ? null
          : FilledButton(
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(DesignTokens.componentButtonPrimaryRounded),
                  ),
                ),
              ),
              onPressed: busy.value || reclaimable == 0 ? null : clear,
              child: Text(busy.value ? '正在清理…' : '清理可释放的暂存'),
            ),
      actions: [
        GlassActionIcon(
          tooltip: '重新检查占用',
          onPressed: busy.value
              ? null
              : () => ref.invalidate(cacheStatusProvider),
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      child: query.when(
        loading: () => const PageChromeBody(
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
        error: (error, _) => PageChromeBody(
          child: EmptyContent(
            icon: LucideIcons.circleAlert,
            title: '暂时无法读取媒体暂存',
            message: failureMessage(error, fallback: '无法读取媒体暂存。请重试。'),
            action: OutlinedButton.icon(
              onPressed: () => ref.invalidate(cacheStatusProvider),
              icon: const Icon(AppIcons.refresh),
              label: const Text('重新检查'),
            ),
          ),
        ),
        data: (data) {
          final used = data.usedBytes;
          final protected = data.protectedBytes;
          final reclaimable = data.reclaimableBytes;
          final reserved = data.reservedBytes;
          final protectedItems = data.protectedItems;
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              SettingsGroup(
                children: [
                  for (final (label, amount, icon, color) in [
                    (
                      '已占用',
                      used,
                      LucideIcons.hardDrive,
                      DesignTokens.colorListIconSlate,
                    ),
                    (
                      '可清理',
                      reclaimable,
                      AppIcons.delete,
                      DesignTokens.colorListIconSlate,
                    ),
                    (
                      '使用中',
                      protected,
                      LucideIcons.lock,
                      DesignTokens.colorListIconSlate,
                    ),
                    (
                      '准备中',
                      reserved,
                      LucideIcons.timer,
                      DesignTokens.colorListIconTransfer,
                    ),
                  ])
                    SettingsRow(
                      title: label,
                      value: _size(amount),
                      icon: icon,
                      color: color,
                    ),
                ],
              ),
              if (!data.spaceVerified)
                const StateNote('暂时无法读取本机剩余空间。请检查存储空间后重试。'),
              if (protectedItems.isNotEmpty) const SectionTitle('受保护原件'),
              for (final item in protectedItems)
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      Text(
                        '${_cacheSourceLabel(devices, item)} · ${_size(item.bytes)}',
                      ),
                      if (item.sourcePath?.isNotEmpty == true)
                        Text(item.sourcePath!),
                      StateNote(item.reason),
                      Wrap(
                        spacing: DesignTokens.spacingSm,
                        children: [
                          if (item.transferId?.isNotEmpty == true)
                            TextButton(
                              onPressed: () =>
                                  TransferDetailsRoute(taskId: item.transferId!)
                                      .push<void>(context),
                              child: const Text('查看传输'),
                            ),
                          if (supportsSystemDocumentSave &&
                              item.canExport &&
                              item.transferId?.isNotEmpty == true)
                            TextButton(
                              onPressed: () =>
                                  DocumentExportRoute(taskId: item.transferId!)
                                      .push<void>(context),
                              child: const Text('保存到系统位置'),
                            ),
                          if (supportsSystemFileShare && item.canShare)
                            TextButton(
                              onPressed: busy.value
                                  ? null
                                  : () async {
                                      busy.value = true;
                                      try {
                                        final result = await sharePreparedFile(
                                          context,
                                          ref,
                                          item.localPath,
                                        );
                                        if (context.mounted && ownsScope()) {
                                          feedback(context, result.message);
                                        }
                                      } catch (error) {
                                        if (context.mounted && ownsScope()) {
                                          feedback(
                                            context,
                                            failureMessage(
                                              error,
                                              fallback:
                                                  '暂时无法确认分享是否完成。请先查看接收文件的应用。',
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (context.mounted && ownsScope()) {
                                          busy.value = false;
                                        }
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

String _cacheSourceLabel(
  List<DeviceSnapshot> devices,
  ProtectedCacheItem item,
) {
  final source = item.sourceLabel;
  final device = devices.where((device) => device.id == source).firstOrNull;
  return device == null ? source : deviceName(device);
}
