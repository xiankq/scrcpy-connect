import 'dart:io';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/models/cached_content.dart';
import 'package:scrcpy_connect/core/content/thumbnail_queue_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content/cached_file_image.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

class MediaThumbnail extends HookConsumerWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    required this.name,
    this.providedPath = '',
    required this.device,
    this.compact = false,
  });
  final String path, name, providedPath;
  final DeviceSnapshot device;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provided = providedPath;
    final retry = useState(0);
    final queue = ref.watch(thumbnailQueueProvider(device.id));
    final lease = useMemoized(
      () => provided.isEmpty ? queue.acquire(path) : null,
      [queue, provided, path, retry.value],
    );
    useEffect(() => lease?.release, [lease]);
    final future = useMemoized(
      () => provided.isNotEmpty
          ? Future<CachedContent>.value(CachedContent(path: provided))
          : lease!.result,
      [provided, lease, retry.value],
    );
    final result = useFuture(future, preserveState: false);
    final source = result.data?.path ?? '';
    Widget placeholder([String? imageFailure]) => Container(
      color: compact
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Theme.of(context).colorScheme.surface,
      child: Center(
        child: result.connectionState != ConnectionState.done
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : compact
            ? GlassActionIcon(
                tooltip: '重试缩略图',
                onPressed: () => retry.value++,
                icon: const Icon(
                  AppIcons.refresh,
                  size: DesignTokens.componentIconActionSize,
                  color: ConnectTokens.coral,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.componentIconButtonSize,
                  minHeight: DesignTokens.componentIconButtonSize,
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingXs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    Flexible(
                      child: Text(
                        imageFailure ??
                            failureMessage(
                              result.error,
                              fallback: '无法显示缩略图。可以打开文件查看。',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: DesignTokens.typographyMicroFontSize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    GlassActionIcon(
                      tooltip: '重试缩略图',
                      onPressed: () => retry.value++,
                      icon: const Icon(
                        AppIcons.refresh,
                        size: DesignTokens.componentIconActionSize,
                        color: ConnectTokens.coral,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: DesignTokens.componentIconButtonSize,
                        minHeight: DesignTokens.componentIconButtonSize,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    if (source.isEmpty) return placeholder();
    return source.startsWith('http')
        ? Image.network(
            source,
            key: ValueKey('$source:${retry.value}'),
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, _, _) => placeholder('缩略图无法显示，请重试。'),
          )
        : Image(
            image: ResizeImage.resizeIfNeeded(
              320,
              null,
              CachedFileImage(File(source), lease: lease?.cacheLease),
            ),
            key: ValueKey('$source:${retry.value}'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder('缩略图无法显示，请重试。'),
          );
  }
}
