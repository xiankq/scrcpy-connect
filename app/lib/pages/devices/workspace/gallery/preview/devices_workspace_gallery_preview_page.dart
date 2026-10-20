import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/widgets/video_preview.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/cached_file_image.dart';
import 'package:scrcpy_connect/widgets/media_controls_protection.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MediaPreviewPage extends HookWidget {
  const MediaPreviewPage({
    super.key,
    required this.controller,
    required this.device,
    required this.file,
  });
  final AppController controller;
  final Json device;
  final Json file;
  @override
  Widget build(BuildContext context) {
    final retry = useState(0);
    final request = useMemoized(
      () => MediaCacheRequest(controller, 'media.preview', {
        'deviceId': device['id'],
        'path': file['path'],
      }),
      [controller, device['id'], file['path'], retry.value],
    );
    useEffect(() => request.dispose, [request]);
    final result = useFuture(request.result, preserveState: false);
    final preview = result.connectionState != ConnectionState.done
        ? const Center(child: CircularProgressIndicator.adaptive())
        : result.hasError
        ? EmptyContent(
            icon: LucideIcons.imageOff,
            title: '无法预览此内容',
            message: '${result.error}',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => retry.value++,
                  child: const Text('重新预览'),
                ),
                TextButton(
                  onPressed: () =>
                      retrieveFile(context, controller, device, file),
                  child: const Text('保存原文件'),
                ),
                TextButton(
                  onPressed: () =>
                      openRemoteRoute(context, deviceId: value(device, 'id')),
                  child: const Text('在手机上查看'),
                ),
              ],
            ),
          )
        : Builder(
            builder: (context) {
              final data = result.data ?? <String, dynamic>{};

              final source = value(data, 'localPath', value(data, 'url'));
              if (source.isEmpty) {
                return EmptyContent(
                  icon: LucideIcons.imageOff,
                  title: '无法预览此格式',
                  message: value(data, 'reason', '可以保存原文件，或在被控手机上查看。'),
                  action: FilledButton(
                    onPressed: () =>
                        retrieveFile(context, controller, device, file),
                    child: const Text('保存原文件'),
                  ),
                );
              }
              if (value(
                file,
                'mime',
                value(data, 'mime'),
              ).startsWith('video')) {
                return VideoPreview(
                  source: source,
                  cacheLease: request.lease,
                  fallback: () =>
                      retrieveFile(context, controller, device, file),
                );
              }
              return ColoredBox(
                color: DesignTokens.colorMediaInk,
                child: Center(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: source.startsWith('http')
                        ? Image.network(
                            source,
                            fit: BoxFit.contain,
                            errorBuilder: (_, e, _) => Text(
                              '$e',
                              style: const TextStyle(color: Colors.white),
                            ),
                          )
                        : Image(
                            image: CachedFileImage(
                              File(source),
                              lease: request.lease,
                            ),
                            fit: BoxFit.contain,
                            errorBuilder: (_, e, _) => Text(
                              '$e',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                ),
              );
            },
          );
    final mediaSource = value(
      result.data ?? {},
      'localPath',
      value(result.data ?? {}, 'url'),
    );
    final reserveChrome =
        result.connectionState != ConnectionState.done ||
        result.hasError ||
        mediaSource.isEmpty;
    final chromeInset =
        MediaQuery.paddingOf(context).top +
        DesignTokens.spacingMd * 2 +
        (MediaQuery.textScalerOf(context)
                    .scale(DesignTokens.typographyBodyFontSize) *
                DesignTokens.typographyBodyLineHeight)
            .clamp(DesignTokens.componentIconButtonSize, double.infinity);
    final inheritedTheme = Theme.of(context);
    final darkTheme = ConnectTokens.theme(Brightness.dark);
    // Media changes material/contrast while retaining the app's typeface.
    final mediaTheme = darkTheme.copyWith(
      textTheme: darkTheme.textTheme.apply(
        fontFamily: inheritedTheme.textTheme.bodyMedium?.fontFamily,
      ),
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
    return Theme(
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
                    top: reserveChrome ? chromeInset : DesignTokens.spacingZero,
                  ),
                  child: preview,
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: MediaControlsProtection(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      child: GlassSurfaceGroup(
                        variant: GlassVariant.clear,
                        child: Row(
                          children: [
                            GlassTooltip(
                              message: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              child: GlassIconButton(
                                semanticLabel: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                size: DesignTokens.componentIconButtonSize,
                                iconSize: DesignTokens.componentIconSize,
                                settings: GlassMaterial.settings(
                                  context,
                                  variant: GlassVariant.clear,
                                ),
                                quality: GlassMaterial.quality(context),
                                interactionScale:
                                    GlassMaterial.reduceMotion(context)
                                    ? 1
                                    : DesignTokens
                                          .componentGlassInteractionScale,
                                anchorStretch: !GlassMaterial.reduceMotion(
                                  context,
                                ),
                                onPressed: () => closePage<void>(context),
                                icon: const Icon(LucideIcons.chevronLeft),
                              ),
                            ),
                            const SizedBox(width: DesignTokens.spacingXs),
                            Expanded(
                              child: Text(
                                value(file, 'name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: DesignTokens.spacingXs),
                            GlassToolbarGroup(
                              variant: GlassVariant.clear,
                              children: [
                                GlassActionIcon(
                                  tooltip: '保存原文件',
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  onPressed: () => retrieveFile(
                                    context,
                                    controller,
                                    device,
                                    file,
                                  ),
                                  icon: const Icon(LucideIcons.download),
                                ),
                                GlassActionIcon(
                                  tooltip: '系统分享',
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  onPressed: () => retrieveFile(
                                    context,
                                    controller,
                                    device,
                                    file,
                                    share: true,
                                  ),
                                  icon: const Icon(LucideIcons.share2),
                                ),
                              ],
                            ),
                          ],
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
    );
  }
}
