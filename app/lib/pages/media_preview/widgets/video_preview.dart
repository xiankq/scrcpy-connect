import 'dart:io';
import 'dart:async';

import 'package:scrcpy_connect/services/media_cache_lease.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

class VideoPreview extends HookWidget {
  const VideoPreview({
    super.key,
    required this.source,
    required this.fallback,
    this.cacheLease,
  });
  final String source;
  final VoidCallback fallback;
  final MediaCacheLease? cacheLease;
  @override
  Widget build(BuildContext context) {
    final player = useMemoized(
      () => source.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(source))
          : VideoPlayerController.file(File(source)),
      [source],
    );
    final future = useMemoized(player.initialize, [player]);
    final initialized = useFuture(future);
    final release = useMemoized(() => cacheLease?.hold(), [player, cacheLease]);
    useEffect(
      () => () {
        unawaited(
          player.dispose().then<void>(
            (_) => release?.call(),
            // Keep protection if the player cannot confirm resource release.
            onError: (Object _, StackTrace _) {},
          ),
        );
      },
      [player, release],
    );
    useListenable(player);
    useOnAppLifecycleStateChange((previous, next) {
      if (next != AppLifecycleState.resumed) player.pause();
    });
    if (initialized.hasError || player.value.hasError) {
      return EmptyContent(
        icon: LucideIcons.videoOff,
        title: '无法预览此视频格式',
        message: '${player.value.errorDescription ?? initialized.error}',
        action: FilledButton(onPressed: fallback, child: const Text('保存原文件')),
      );
    }
    if (!player.value.isInitialized) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return ColoredBox(
      color: DesignTokens.colorMediaInk,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
          ),
          Positioned(
            left: DesignTokens.spacingMd,
            right: DesignTokens.spacingMd,
            bottom: DesignTokens.spacingMd,
            child: Glass(
              variant: GlassVariant.clear,
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Column(
                children: [
                  VideoProgressIndicator(
                    player,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: Theme.of(context).colorScheme.primary,
                      bufferedColor: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .24),
                      backgroundColor: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .08),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: player.value.isPlaying ? '暂停' : '播放',
                        onPressed: () => player.value.isPlaying
                            ? player.pause()
                            : player.play(),
                        icon: Icon(
                          player.value.isPlaying
                              ? LucideIcons.pause
                              : LucideIcons.play,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${player.value.position.inMinutes}:${(player.value.position.inSeconds % 60).toString().padLeft(2, '0')} / ${player.value.duration.inMinutes}:${(player.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        ),
                      ),
                      IconButton(
                        tooltip: player.value.volume == 0 ? '打开声音' : '静音',
                        onPressed: () =>
                            player.setVolume(player.value.volume == 0 ? 1 : 0),
                        icon: Icon(
                          player.value.volume == 0
                              ? LucideIcons.volumeX
                              : LucideIcons.volume2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
