import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_controls_protection.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_preview_toolbar.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/video_preview.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content/cached_file_image.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/media_cache_blocker.dart';

class MediaPreviewPage extends HookConsumerWidget {
  const MediaPreviewPage({super.key, required this.device, required this.file});
  final DeviceSnapshot device;
  final FileCatalogEntry file;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentReaderProvider);
    final video = file.mime.startsWith('video/');
    final retry = useState(0);
    final originalSize = useState(false);
    void retrieve() =>
        retrieveFile(context, ref, device, file, openAfterTransfer: true);
    final request = useMemoized(
      () => video
          ? null
          : ContentCacheRequest(
              () =>
                  content.preview(deviceId: device.id, path: (file.path ?? '')),
              content.releaseLease,
              leaseId: (content) => content.leaseId,
            ),
      [content, device.id, file.path, video, retry.value],
    );
    useEffect(() => request?.dispose, [request]);
    final result = useFuture(request?.result, preserveState: false);
    final preview = video
        ? VideoPreview(fallback: retrieve)
        : result.connectionState != ConnectionState.done
        ? const Center(child: CircularProgressIndicator.adaptive())
        : result.hasError
        ? EmptyContent(
            icon: LucideIcons.imageOff,
            title: '无法预览此内容',
            message: '${result.error}',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMediaCacheAdmissionFailure(result.error))
                  const MediaCacheBlocker(),
                OutlinedButton(
                  onPressed: () => retry.value++,
                  child: const Text('重新预览'),
                ),
                TextButton(onPressed: retrieve, child: const Text('取回文件')),
                TextButton(
                  onPressed: () =>
                      openRemoteRoute(context, deviceId: device.id),
                  child: const Text('在手机上查看'),
                ),
              ],
            ),
          )
        : Builder(
            builder: (context) {
              final data = result.data;
              final source = data?.path ?? '';
              if (source.isEmpty) {
                return EmptyContent(
                  icon: LucideIcons.imageOff,
                  title: '无法预览此格式',
                  message: data?.reason ?? '可以保存原文件，或在被控手机上查看。',
                  action: FilledButton(
                    onPressed: retrieve,
                    child: const Text('取回文件'),
                  ),
                );
              }
              return ColoredBox(
                color: DesignTokens.colorMediaInk,
                child: InteractiveViewer(
                  key: ValueKey(originalSize.value),
                  constrained: !originalSize.value,
                  minScale: .5,
                  maxScale: 5,
                  child: Image(
                    image: source.startsWith('http')
                        ? NetworkImage(source)
                        : CachedFileImage(File(source), lease: request?.lease),
                    fit: originalSize.value ? BoxFit.none : BoxFit.contain,
                    errorBuilder: (_, e, _) => Center(
                      child: Text(
                        '$e',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
    final mediaSource = result.data?.path ?? '';
    final reserveChrome =
        video ||
        result.connectionState != ConnectionState.done ||
        result.hasError ||
        mediaSource.isEmpty;
    final actions = <(String, IconData, VoidCallback)>[
      ('取回文件', LucideIcons.download, retrieve),
      if (supportsSystemFileShare)
        (
          '分享',
          LucideIcons.share2,
          () => retrieveFile(context, ref, device, file, share: true),
        ),
      if (!reserveChrome)
        (
          originalSize.value ? '适合屏幕' : '原尺寸',
          originalSize.value ? LucideIcons.minimize2 : LucideIcons.maximize2,
          () => originalSize.value = !originalSize.value,
        ),
    ];
    final chromeInset =
        MediaQuery.paddingOf(context).top +
        DesignTokens.spacingMd * 2 +
        (MediaQuery.textScalerOf(context)
                    .scale(DesignTokens.typographyBodyFontSize) *
                DesignTokens.typographyBodyLineHeight)
            .clamp(DesignTokens.componentIconButtonSize, double.infinity);
    final inheritedTheme = Theme.of(context);
    final darkTheme = ConnectTokens.theme(
      Brightness.dark,
      fontFamily: inheritedTheme.textTheme.bodyMedium?.fontFamily,
      fontFamilyFallback:
          inheritedTheme.textTheme.bodyMedium?.fontFamilyFallback,
    );
    // 媒体只调整材质和对比度，保留应用字体。
    final mediaTheme = darkTheme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: darkTheme.filledButtonTheme.style?.copyWith(
          textStyle: inheritedTheme.filledButtonTheme.style?.textStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: darkTheme.outlinedButtonTheme.style?.copyWith(
          textStyle: inheritedTheme.outlinedButtonTheme.style?.textStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: darkTheme.textButtonTheme.style?.copyWith(
          textStyle: inheritedTheme.textButtonTheme.style?.textStyle,
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: mediaTheme,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: DesignTokens.colorMediaInk,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: reserveChrome
                          ? chromeInset
                          : DesignTokens.spacingZero,
                      bottom: reserveChrome
                          ? MediaQuery.paddingOf(context).bottom +
                                DesignTokens.componentFileActionBarHeight +
                                DesignTokens.spacingMd * 2
                          : DesignTokens.spacingZero,
                    ),
                    child: preview,
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: MediaPreviewToolbar(
                    title: file.name,
                    onBack: () => closePage<void>(context),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: MediaControlsProtection(
                    edge: MediaControlsEdge.bottom,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.all(DesignTokens.spacingMd),
                      child: Center(
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth:
                                DesignTokens.componentMediaPreviewBarWidth,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) => GlassToolbarGroup(
                              variant: GlassVariant.clear,
                              children: [
                                for (final (label, icon, onPressed) in actions)
                                  SizedBox(
                                    width:
                                        constraints.maxWidth / actions.length,
                                    child: Tooltip(
                                      message: label,
                                      excludeFromSemantics: true,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(
                                            0,
                                            DesignTokens
                                                .componentFileActionBarHeight,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: DesignTokens.spacingXs,
                                          ),
                                          foregroundColor:
                                              DesignTokens.colorWhite,
                                        ),
                                        onPressed: onPressed,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              icon,
                                              size: DesignTokens
                                                  .componentIconActionSize,
                                            ),
                                            const SizedBox(
                                              height: DesignTokens.spacingMicro,
                                            ),
                                            Text(
                                              label,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
