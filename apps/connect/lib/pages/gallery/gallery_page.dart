import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class GalleryPage extends HookWidget {
  const GalleryPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final selected = useState<Set<String>>({});
    return PageFrame(
      title: '手机相册',
      subtitle: deviceName(device),
      actions: [
        IconButton(
          tooltip: selected.value.isEmpty ? '选择照片' : '取消选择',
          onPressed: () =>
              selected.value = selected.value.isEmpty ? {'__select__'} : {},
          icon: Icon(
            selected.value.isEmpty ? LucideIcons.squareCheck : LucideIcons.x,
          ),
        ),
      ],
      child: CommandView(
        controller: controller,
        command: 'media.list',
        params: {'deviceId': device['id']},
        emptyTitle: '暂时无法读取相册',
        alternative: TextButton(
          onPressed: () =>
              openRemoteRoute(context, deviceId: value(device, 'id')),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data, refresh) {
          final media = objects(data['items']);
          if (media.isEmpty) {
            return EmptyContent(
              icon: LucideIcons.images,
              title: '相册中没有可显示的内容',
              message: value(data, 'reason', '确认设备连接与目录权限后重新检查。'),
              action: OutlinedButton(
                onPressed: refresh,
                child: const Text('重新检查'),
              ),
            );
          }
          return Column(
            children: [
              if (selected.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已选择 ${selected.value.where((e) => e != '__select__').length} 项',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await retrieveSelection(
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
                          );
                        },
                        icon: const Icon(LucideIcons.download, size: 18),
                        label: const Text('保存原文件'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => refresh(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: media.length,
                    itemBuilder: (context, i) {
                      final file = media[i];
                      final path = value(file, 'path');
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: !fileCanOpen(file)
                            ? null
                            : () {
                                if (selected.value.isNotEmpty) {
                                  final next = {...selected.value};
                                  next.contains(path)
                                      ? next.remove(path)
                                      : next.add(path);
                                  selected.value = next;
                                } else {
                                  MediaPreviewRoute(
                                    deviceId: value(device, 'id'),
                                    path: value(file, 'path'),
                                  ).push<void>(context);
                                }
                              },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (!fileCanOpen(file))
                                Container(
                                  color: Theme.of(context).colorScheme.surface,
                                  padding: const EdgeInsets.all(12),
                                  child: Center(
                                    child: Text(
                                      fileUnavailableReason(file),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                )
                              else
                                MediaThumbnail(
                                  file: file,
                                  controller: controller,
                                  device: device,
                                ),
                              if (value(file, 'mime').startsWith('video'))
                                const Positioned(
                                  left: 8,
                                  bottom: 8,
                                  child: Icon(
                                    LucideIcons.play,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              if (selected.value.contains(path))
                                Container(
                                  color: Colors.black38,
                                  child: const Icon(
                                    LucideIcons.circleCheck,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
