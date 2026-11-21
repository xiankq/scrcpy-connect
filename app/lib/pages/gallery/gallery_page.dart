import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/gallery/gallery_history_notifier.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan_notifier.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner_provider.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/gallery/widgets/gallery_media_tile.dart';
import 'package:scrcpy_connect/pages/gallery/widgets/gallery_scan_summary.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class GalleryPage extends HookConsumerWidget {
  const GalleryPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(galleryHistoryProvider.notifier);
    final source = ref.watch(galleryScannerProvider);
    final identity = (id: device.id, guid: device.guid, serial: device.serial);
    final selected = useMemoized(() => ValueNotifier<Set<String>>({}), [
      source,
      identity,
    ]);
    useEffect(() => selected.dispose, [selected]);
    useListenable(selected);
    final previous = useMemoized(() => history.read(device), [
      source,
      identity,
    ]);
    final scroll = useScrollController(
      initialScrollOffset: previous?.scrollOffset ?? 0,
      keys: [source, identity],
      keepScrollOffset: false,
    );
    final lastScrollOffset = useMemoized(
      () => ObjectRef(previous?.scrollOffset ?? 0.0),
      [source, identity],
    );
    useEffect(() {
      void rememberOffset() {
        if (scroll.hasClients) lastScrollOffset.value = scroll.offset;
      }

      scroll.addListener(rememberOffset);
      return () => scroll.removeListener(rememberOffset);
    }, [scroll]);
    final scope = useMemoized(Object.new, [source, identity]);
    final provider = galleryScanProvider(device, scope: scope);
    final scan = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final visible = useMemoized(() => ObjectRef(scan), [scope])..value = scan;
    useEffect(() {
      scheduleMicrotask(actions.start);
      return () {
        final saved = visible.value;
        if (saved.result case final result?) {
          final offset = lastScrollOffset.value;
          scheduleMicrotask(
            () => history.save(
              device,
              result,
              saved.items,
              offset,
              source: source,
            ),
          );
        }
      };
    }, [actions, history, source]);
    final status = scan.result?.status;
    final media = scan.items;
    Future<void> reload() async {
      if (selected.value.isNotEmpty || scan.scanning) return;
      await actions.start();
    }

    useEffect(() {
      if (scan.canLoadMore && !scan.paging && scan.error == null) {
        scheduleMicrotask(() {
          if (context.mounted) actions.loadMore();
        });
      }
      return null;
    }, [actions, scan.result?.nextOffset, scan.paging, scan.error]);

    final selecting = selected.value.isNotEmpty;
    final chosen = media.where((file) => selected.value.contains(file.path));
    return PageFrame(
      title: selecting ? '已选择 ${chosen.length} 项' : '手机相册',
      onBack: selecting ? () => selected.value = {} : null,
      bottomRadius: DesignTokens.roundedFull,
      bottom: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!selecting)
            Expanded(
              child: _GalleryAction(
                label: '刷新',
                icon: LucideIcons.refreshCw,
                onPressed: scan.scanning ? null : reload,
              ),
            ),
          if (selecting)
            Expanded(
              child: _GalleryAction(
                label: '取回原件',
                icon: LucideIcons.download,
                onPressed: chosen.isEmpty
                    ? null
                    : () => retrieveSelection(
                        context,
                        ref,
                        device,
                        chosen
                            .map(
                              (file) => (
                                path: file.path,
                                name: file.name,
                                canOpen: file.canOpen,
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
          Expanded(
            child: _GalleryAction(
              label: selecting ? '取消选择' : '选择',
              icon: selecting ? LucideIcons.x : LucideIcons.squareCheck,
              onPressed: media.isEmpty
                  ? null
                  : () => selected.value = selecting ? {} : {'__select__'},
            ),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: reload,
        child: CustomScrollView(
          key: ValueKey((source, device.id)),
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
                      onCancel: actions.cancel,
                      onRefresh: actions.refresh,
                      device: device,
                      onRestart: reload,
                      onUpdate: selected.value.isNotEmpty
                          ? null
                          : () {
                              actions.applyUpdate();
                              lastScrollOffset.value = 0;
                              if (scroll.hasClients) scroll.jumpTo(0);
                            },
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
                  message: status == .completed
                      ? '此范围没有识别到照片或视频；应用私有内容请在手机原应用中查看。'
                      : '未读目录仍可能包含照片或视频，可重新检查或在手机上继续。',
                  action: TextButton(
                    onPressed: () =>
                        openRemoteRoute(context, deviceId: device.id),
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
                  final path = file.path;
                  return GalleryMediaTile(
                    file: file,
                    device: device,
                    selected: selected.value.contains(path),
                    onTap: () {
                      if (path == null || path.isEmpty) return;
                      if (selected.value.isNotEmpty) {
                        final next = {...selected.value};
                        next.contains(path)
                            ? next.remove(path)
                            : next.add(path);
                        selected.value = next;
                      } else {
                        MediaPreviewRoute(
                          deviceId: device.id,
                          path: path,
                        ).push<void>(context);
                      }
                    },
                  );
                },
              ),
            ),
            if (scan.paging)
              const SliverToBoxAdapter(
                child: Center(child: ContentLoadingIndicator()),
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

class _GalleryAction extends StatelessWidget {
  const _GalleryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: DesignTokens.componentIconSize),
        const SizedBox(height: DesignTokens.spacingXxs),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}
