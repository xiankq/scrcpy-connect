import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/widgets/gallery_scope_sheet.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/services/gallery_scan.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class GalleryPage extends HookWidget {
  const GalleryPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final selected = useMemoized(() => ValueNotifier<Set<String>>({}), [
      controller,
      device['id'],
    ]);
    useEffect(() => selected.dispose, [selected]);
    useListenable(selected);
    final scan = useMemoized(
      () => GalleryScan(controller, value(device, 'id')),
      [controller, device['id']],
    );
    useListenable(scan);
    useEffect(() {
      scheduleMicrotask(scan.start);
      return scan.dispose;
    }, [scan]);
    final data = scan.result ?? <String, dynamic>{};
    final status = value(data, 'status');
    final media = scan.items;
    Future<void> reload() async {
      selected.value = {};
      await scan.start();
    }

    return PageFrame(
      title: '手机相册',

      actions: [
        IconButton(
          tooltip: '重新检查相册',
          onPressed: reload,
          icon: const Icon(LucideIcons.refreshCw),
        ),
        IconButton(
          tooltip: selected.value.isEmpty ? '选择照片' : '取消选择',
          onPressed: media.isEmpty
              ? null
              : () => selected.value = selected.value.isEmpty
                    ? {'__select__'}
                    : {},
          icon: Icon(
            selected.value.isEmpty ? LucideIcons.squareCheck : LucideIcons.x,
          ),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacingMd,
                  DesignTokens.spacingXs,
                  DesignTokens.spacingMd,
                  DesignTokens.spacingSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scan.scanning
                          ? '正在检查手机中的照片与视频'
                          : switch (status) {
                              'partial' => '部分目录未能检查',
                              'cancelled' => '已停止检查',
                              'completed' => '已检查共享存储中的照片与视频',
                              _ => '暂时无法读取相册',
                            },
                      style: status == 'completed' && !scan.scanning
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final details = Text(
                          scan.scanning
                              ? '已检查 ${data['visitedDirectories'] ?? 0} 个文件夹、${data['visitedEntries'] ?? 0} 项'
                              : '已显示 ${media.length} / ${data['total'] ?? 0} 项 · 按文件修改时间排列',
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                        if (scan.result == null) return details;
                        final scopeAction = TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(
                              DesignTokens.componentIconButtonSize,
                              DesignTokens.componentIconButtonSize,
                            ),
                          ),
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => GalleryScopeSheet(
                              device: device,
                              snapshot: data,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text('相册范围与未读项目')),
                              SizedBox(width: DesignTokens.spacingXs),
                              Icon(
                                LucideIcons.chevronUp,
                                size: DesignTokens.componentIconSmallSize,
                              ),
                            ],
                          ),
                        );
                        final scopeLabelWidth = MediaQuery.textScalerOf(context)
                            .scale(
                              DesignTokens.typographyLabelFontSize *
                                  '相册范围与未读项目'.length,
                            );
                        if (scopeLabelWidth +
                                DesignTokens.componentIconSmallSize +
                                DesignTokens.spacingLg * 2 >
                            constraints.maxWidth) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              details,
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: scopeAction,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: details),
                            const SizedBox(width: DesignTokens.spacingSm),
                            Flexible(child: scopeAction),
                          ],
                        );
                      },
                    ),
                    if (scan.scanning) ...[
                      const SizedBox(height: DesignTokens.spacingSm),
                      const LinearProgressIndicator(minHeight: 2),
                      TextButton(
                        onPressed: scan.scanId == null || scan.stopping
                            ? null
                            : scan.cancel,
                        child: Text(scan.stopping ? '正在停止检查' : '停止检查'),
                      ),
                    ],
                    if (scan.error != null) ...[
                      StateNote(scan.error!),
                      TextButton(
                        onPressed: scan.scanId == null ? reload : scan.refresh,
                        child: const Text('重新核验本次检查'),
                      ),
                    ],
                    if (selected.value.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '已选择 ${selected.value.where((e) => e != '__select__').length} 项',
                            ),
                          ),
                          TextButton.icon(
                            onPressed:
                                selected.value.any(
                                  (path) => path != '__select__',
                                )
                                ? () => retrieveSelection(
                                    context,
                                    controller,
                                    device,
                                    media
                                        .where(
                                          (file) => selected.value.contains(
                                            value(file, 'path'),
                                          ),
                                        )
                                        .toList(),
                                  )
                                : null,
                            icon: const Icon(
                              LucideIcons.download,
                              size: DesignTokens.componentIconActionSize,
                            ),
                            label: const Text('保存原文件'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (media.isEmpty && !scan.scanning)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyContent(
                  icon: LucideIcons.images,
                  title: scan.result == null ? '相册检查未完成' : '已检查范围内没有可显示的内容',
                  message: status == 'completed'
                      ? '此范围没有识别到照片或视频；应用私有内容请在手机原应用中查看。'
                      : '未读目录仍可能包含照片或视频，可重新检查或在手机上继续。',
                  action: TextButton(
                    onPressed: () =>
                        openRemoteRoute(context, deviceId: value(device, 'id')),
                    child: const Text('在手机上继续处理'),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  crossAxisSpacing: DesignTokens.spacingXs,
                  mainAxisSpacing: DesignTokens.spacingXs,
                ),
                itemCount: media.length,
                itemBuilder: (context, i) {
                  final file = media[i];
                  final path = value(file, 'path');
                  return Semantics(
                    label: value(file, 'name'),
                    selected: selected.value.contains(path),
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.roundedMd,
                      ),
                      onTap: !fileCanOpen(file)
                          ? null
                          : () {
                              if (selected.value.isNotEmpty) {
                                final next = {...selected.value};
                                next.contains(path)
                                    ? next.remove(path)
                                    : next.add(path);
                                selected.value = next;
                              } else {
                                MediaPreviewRoute(
                                  deviceId: value(device, 'id'),
                                  path: value(file, 'path'),
                                ).push<void>(context);
                              }
                            },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.roundedMd,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (!fileCanOpen(file))
                              Container(
                                color: Theme.of(context).colorScheme.surface,
                                padding: const EdgeInsets.all(
                                  DesignTokens.spacingSm,
                                ),
                                child: Center(
                                  child: Text(
                                    fileUnavailableReason(file),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              )
                            else
                              MediaThumbnail(
                                file: file,
                                controller: controller,
                                device: device,
                              ),
                            if (value(file, 'mime').startsWith('video'))
                              const Positioned(
                                left: 8,
                                bottom: 8,
                                child: Icon(
                                  LucideIcons.play,
                                  color: Colors.white,
                                  size: DesignTokens.componentIconActionSize,
                                ),
                              ),
                            if (selected.value.contains(path))
                              Container(
                                color: Colors.black38,
                                child: const Icon(
                                  LucideIcons.circleCheck,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (scan.nextOffset != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: OutlinedButton(
                    onPressed: scan.paging ? null : scan.loadMore,
                    child: Text(scan.paging ? '正在加载' : '加载更多'),
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: DesignTokens.spacingLg),
            ),
          ],
        ),
      ),
    );
  }
}
