import 'dart:async';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/gallery_scan_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/file_actions.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'widgets/gallery_media_tile.dart';
import 'widgets/gallery_scan_summary.dart';

class GalleryPage extends HookWidget {
  const GalleryPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppStore controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final selected = useMemoized(() => ValueNotifier<Set<String>>({}), [
      controller,
      device['id'],
    ]);
    useEffect(() => selected.dispose, [selected]);
    useListenable(selected);
    final previous = useMemoized(() => controller.galleryHistory.read(device), [
      controller,
      device['id'],
    ]);
    final scroll = useScrollController(
      initialScrollOffset: previous?.scrollOffset ?? 0,
      keys: [controller, device['id']],
      keepScrollOffset: false,
    );
    final lastScrollOffset = useMemoized(
      () => ObjectRef(previous?.scrollOffset ?? 0.0),
      [controller, device['id']],
    );
    useEffect(() {
      void rememberOffset() {
        if (scroll.hasClients) lastScrollOffset.value = scroll.offset;
      }

      scroll.addListener(rememberOffset);
      return () => scroll.removeListener(rememberOffset);
    }, [scroll]);
    final scan = useMemoized(
      () => GalleryScanController(
        controller.execute,
        value(device, 'id'),
        previous: previous,
      ),
      [controller, device['id']],
    );
    useListenable(scan);
    useEffect(() {
      scheduleMicrotask(scan.start);
      return () {
        if (scan.result != null) {
          controller.galleryHistory.save(
            device,
            scan.result!,
            scan.items,
            lastScrollOffset.value,
          );
        }
        scan.dispose();
      };
    }, [scan]);
    final data = scan.result ?? <String, dynamic>{};
    final status = value(data, 'status');
    final media = scan.items;
    Future<void> reload() async {
      if (selected.value.isNotEmpty || scan.scanning) return;
      await scan.start();
    }

    return PageFrame(
      title: '手机相册',

      actions: [
        GlassActionIcon(
          tooltip: '重新检查相册',
          onPressed: selected.value.isNotEmpty || scan.scanning ? null : reload,
          icon: const Icon(LucideIcons.refreshCw),
        ),
        GlassActionIcon(
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
          key: ValueKey((controller, device['id'])),
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const PageChromeSliver(),
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
                    GalleryScanSummary(
                      scan: scan,
                      device: device,
                      onRestart: reload,
                      onUpdate: selected.value.isNotEmpty
                          ? null
                          : () {
                              scan.applyUpdate();
                              lastScrollOffset.value = 0;
                              if (scroll.hasClients) scroll.jumpTo(0);
                            },
                    ),
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
                  return GalleryMediaTile(
                    file: file,
                    controller: controller,
                    device: device,
                    selected: selected.value.contains(path),
                    onTap: () {
                      if (selected.value.isNotEmpty) {
                        final next = {...selected.value};
                        next.contains(path)
                            ? next.remove(path)
                            : next.add(path);
                        selected.value = next;
                      } else {
                        MediaPreviewRoute(
                          deviceId: value(device, 'id'),
                          path: path,
                        ).push<void>(context);
                      }
                    },
                  );
                },
              ),
            ),
            if (scan.canLoadMore)
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
            const PageChromeBottomSliver(),
          ],
        ),
      ),
    );
  }
}
