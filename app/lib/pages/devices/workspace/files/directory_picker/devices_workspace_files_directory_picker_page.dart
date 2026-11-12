import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

class ShareDirectoryPickerPage extends HookConsumerWidget {
  const ShareDirectoryPickerPage({
    super.key,
    required this.controller,
    required this.device,
    required this.initialPath,
  });
  final AppNotifier controller;
  final DeviceSnapshot device;
  final String initialPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = useState(
      initialPath.startsWith('/') ? initialPath : '/sdcard',
    );
    final provider = fileDirectoryProvider((
      deviceId: device.id,
      path: path.value,
    ));
    final query = ref.watch(provider);
    Future<void> refresh() => ref.read(provider.notifier).refresh();
    return PageFrame(
      title: '选择目标目录',
      child: Builder(
        builder: (context) => NestedScrollView(
          headerSliverBuilder: (context, innerScrolled) => [
            const PageChromeSliver(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Row(
                  children: [
                    GlassActionIcon(
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
            ),
          ],
          body: PageChromePadding.removeTop(
            context: context,
            child: AsyncContent(
              loading: query.loading,
              data: query.data,
              error: query.error,
              onRefresh: refresh,
              emptyTitle: '无法读取这个目录',
              builder: (context, data) {
                final directories = data.entries
                    .where((entry) => entry.isDirectory)
                    .toList();
                return GroupedListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingZero,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
                  itemCount: directories.length + 1,
                  itemBuilder: (context, index) {
                    if (index < directories.length) {
                      final directory = directories[index];
                      return ActionRow(
                        key: ValueKey(directory.path),
                        icon: LucideIcons.folder,
                        title: directory.name,
                        onTap:
                            directory.path?.isNotEmpty != true ||
                                !directory.canOpen ||
                                !query.verified
                            ? null
                            : () => path.value = directory.path!,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (directories.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(DesignTokens.spacingMd),
                            child: Text('此目录没有子文件夹'),
                          ),
                        const SizedBox(height: DesignTokens.spacingLg),
                        FilledButton(
                          onPressed: query.verified
                              ? () => closePage<String>(context, path.value)
                              : null,
                          child: const Text('使用这个目录'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
