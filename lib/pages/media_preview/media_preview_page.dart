import 'package:scrcpy_connect/pages/media_preview/widgets/video_preview.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/cached_file_image.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

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
    return PageFrame(
      title: value(file, 'name'),
      subtitle: deviceName(device),
      actions: [
        IconButton(
          tooltip: '保存原文件',
          onPressed: () => retrieveFile(context, controller, device, file),
          icon: const Icon(LucideIcons.download),
        ),
        IconButton(
          tooltip: '系统分享',
          onPressed: () =>
              retrieveFile(context, controller, device, file, share: true),
          icon: const Icon(LucideIcons.share2),
        ),
      ],
      child: result.connectionState != ConnectionState.done
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
                  color: const Color(0xff111114),
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
            ),
    );
  }
}
