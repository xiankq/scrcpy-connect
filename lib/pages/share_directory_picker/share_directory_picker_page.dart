import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ShareDirectoryPickerPage extends HookWidget {
  const ShareDirectoryPickerPage({
    super.key,
    required this.controller,
    required this.device,
    required this.initialPath,
  });
  final AppController controller;
  final Json device;
  final String initialPath;
  @override
  Widget build(BuildContext context) {
    final path = useState(
      initialPath.startsWith('/') ? initialPath : '/sdcard',
    );
    return PageFrame(
      title: '选择目标目录',
      subtitle: deviceName(device),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一级',
                  onPressed: path.value == '/'
                      ? null
                      : () {
                          final parts = path.value
                              .split('/')
                              .where((part) => part.isNotEmpty)
                              .toList();
                          if (parts.isNotEmpty) parts.removeLast();
                          path.value = '/${parts.join('/')}';
                        },
                  icon: const Icon(LucideIcons.arrowUp),
                ),
                Expanded(child: Text(path.value)),
              ],
            ),
          ),
          Expanded(
            child: CommandView(
              controller: controller,
              command: 'files.list',
              params: {'deviceId': device['id'], 'path': path.value},
              emptyTitle: '无法读取这个目录',
              builder: (context, data, refresh) {
                final directories = objects(data['entries'] ?? data['files'])
                    .where(
                      (entry) =>
                          entry['isDirectory'] == true ||
                          entry['type'] == 'directory',
                    )
                    .toList();
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          for (final directory in directories)
                            ListTile(
                              leading: const Icon(LucideIcons.folder),
                              title: Text(value(directory, 'name')),
                              subtitle:
                                  directory['path'] is! String ||
                                      directory['canOpen'] == false
                                  ? Text(
                                      value(
                                        directory,
                                        'reason',
                                        '文件名无法解析为有效路径。',
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(LucideIcons.chevronRight),
                              onTap:
                                  directory['path'] is! String ||
                                      directory['canOpen'] == false
                                  ? null
                                  : () => path.value = value(directory, 'path'),
                            ),
                          if (directories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('此目录没有子文件夹'),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                closePage<String>(context, path.value),
                            child: const Text('使用这个目录'),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
