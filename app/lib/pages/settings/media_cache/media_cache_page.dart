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
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/page_loader.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

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
            danger: true,
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
        loading: () => const PageChromeBody(child: PageLoader()),
        error: (error, _) => PageChromeBody(
          child: EmptyContent(
            icon: LucideIcons.circleAlert,
            title: '暂时无法读取媒体暂存',
            message: failureMessage(error, fallback: '无法读取媒体暂存。请重试。'),
            action: AppButton(
              role: AppButtonRole.secondaryOnPage,
              onPressed: () => ref.invalidate(cacheStatusProvider),
              icon: AppIcons.refresh,
              label: '重新检查',
            ),
          ),
        ),
        data: (data) {
          final used = data.usedBytes;
          final protected = data.protectedBytes;
          final reclaimable = data.reclaimableBytes;
          final reserved = data.reservedBytes;
          final protectedItems = data.protectedItems;
          final colors = AppColors.of(context);
          final type = AppTypography.of(context);
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
            children: [
              SettingsGroup(
                children: [
                  for (final (label, detail, amount) in [
                    ('已占用', null, used),
                    ('可清理', '已完成且未在使用的副本', reclaimable),
                    ('使用中', '正在传输或预览，暂不清理', protected),
                    ('准备中', null, reserved),
                  ])
                    AppListRow(
                      title: Text(label),
                      subtitle: detail == null ? null : Text(detail),
                      value: _size(amount),
                    ),
                ],
              ),
              const SectionFooter('清理只删除本机暂存副本，手机原件和已保存到系统的文件均会保留。'),
              if (!data.spaceVerified)
                const StateNote('暂时无法读取本机剩余空间。请检查存储空间后重试。'),
              if (protectedItems.isNotEmpty) const SectionTitle('受保护原件'),
              for (final item in protectedItems)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingMd,
                  ),
                  child: ContentPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: type.headline),
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Text(
                          '${_cacheSourceLabel(devices, item)} · ${_size(item.bytes)}',
                          style: type.subheadline.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (item.sourcePath?.isNotEmpty == true)
                          Text(
                            item.sourcePath!,
                            style: type.footnote.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        StateNote(item.reason),
                        Wrap(
                          spacing: DesignTokens.spacingSm,
                          runSpacing: DesignTokens.spacingSm,
                          children: [
                            if (item.transferId?.isNotEmpty == true)
                              AppButton(
                                size: AppButtonSize.section,
                                onPressed: () => TransferDetailsRoute(
                                  taskId: item.transferId!,
                                ).push<void>(context),
                                label: '查看传输',
                              ),
                            if (supportsSystemDocumentSave &&
                                item.canExport &&
                                item.transferId?.isNotEmpty == true)
                              AppButton(
                                size: AppButtonSize.section,
                                onPressed: () => DocumentExportRoute(
                                  taskId: item.transferId!,
                                ).push<void>(context),
                                label: '保存到系统位置',
                              ),
                            if (supportsSystemFileShare && item.canShare)
                              AppButton(
                                size: AppButtonSize.section,
                                onPressed: busy.value
                                    ? null
                                    : () async {
                                        busy.value = true;
                                        try {
                                          final result =
                                              await sharePreparedFile(
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
                                label: '系统分享',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (outcome.value != null) StateNote(outcome.value!),
              const SizedBox(height: DesignTokens.componentListSectionGap),
              // 危险动作：页面上的通栏胶囊（design.md「列表」危险动作）。
              AppButton(
                role: AppButtonRole.destructiveOnPage,
                expand: true,
                icon: AppIcons.delete,
                onPressed: busy.value || reclaimable == 0 ? null : clear,
                label: busy.value ? '正在清理…' : '清理可释放的暂存',
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

String _cacheSourceLabel(
  List<DeviceSnapshot> devices,
  ProtectedCacheItem item,
) {
  final source = item.sourceLabel;
  final device = devices.where((device) => device.id == source).firstOrNull;
  return device == null ? source : deviceName(device);
}
