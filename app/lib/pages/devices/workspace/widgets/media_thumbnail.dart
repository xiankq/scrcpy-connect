import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/stores/media/thumbnail_queue.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/cached_file_image.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MediaThumbnail extends HookConsumerWidget {
  const MediaThumbnail({
    super.key,
    required this.file,
    required this.controller,
    required this.device,
    this.compact = false,
  });
  final Json file;
  final AppController controller;
  final Json device;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provided = value(file, 'thumbnail', value(file, 'localPath'));
    final retry = useState(0);
    final queue = ref.watch(
      thumbnailQueueProvider(controller, value(device, 'id')),
    );
    final lease = useMemoized(
      () => provided.isEmpty ? queue.acquire(value(file, 'path')) : null,
      [queue, provided, file['path'], retry.value],
    );
    useEffect(() => lease?.release, [lease]);
    final future = useMemoized(
      () => provided.isNotEmpty
          ? Future<Json>.value({'localPath': provided})
          : lease!.result,
      [provided, lease, retry.value],
    );
    final result = useFuture(future, preserveState: false);
    final source = value(
      result.data ?? {},
      'localPath',
      value(result.data ?? {}, 'url'),
    );
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
                  LucideIcons.refreshCw,
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
                      value(file, 'name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    Flexible(
                      child: Text(
                        imageFailure ?? '缩略图未能显示：${result.error ?? '未收到可用缩略图'}',
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
                        LucideIcons.refreshCw,
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
