import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MediaThumbnail extends HookWidget {
  const MediaThumbnail({
    super.key,
    required this.file,
    required this.controller,
    required this.device,
  });
  final Json file;
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final provided = value(file, 'thumbnail', value(file, 'localPath'));
    final future = useMemoized(
      () => provided.isNotEmpty
          ? Future<Json>.value({'localPath': provided})
          : controller.request('media.thumbnail', {
              'deviceId': device['id'],
              'path': file['path'],
            }),
      [provided, file['path'], device['id']],
    );
    final result = useFuture(future);
    final source = value(
      result.data ?? {},
      'localPath',
      value(result.data ?? {}, 'url'),
    );
    Widget placeholder() => Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: result.connectionState != ConnectionState.done
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.image, color: ConnectTokens.coral),
                    const SizedBox(height: 8),
                    Text(
                      value(file, 'name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
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
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, _, _) => placeholder(),
          )
        : Image.file(
            File(source),
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, _, _) => placeholder(),
          );
  }
}
