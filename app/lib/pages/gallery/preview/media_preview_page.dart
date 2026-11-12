import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_preview_toolbar.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/video_preview.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content/cached_file_image.dart';
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
        ? VideoPreview(fallback: () => retrieveFile(context, ref, device, file))
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
                TextButton(
                  onPressed: () => retrieveFile(context, ref, device, file),
                  child: const Text('保存原文件'),
                ),
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
                    onPressed: () => retrieveFile(context, ref, device, file),
                    child: const Text('保存原文件'),
                  ),
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
                              lease: request?.lease,
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
    final mediaSource = result.data?.path ?? '';
    final reserveChrome =
        video ||
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
                child: MediaPreviewToolbar(
                  title: file.name,
                  onBack: () => closePage<void>(context),
                  onSave: () => retrieveFile(context, ref, device, file),
                  onShare: () =>
                      retrieveFile(context, ref, device, file, share: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
