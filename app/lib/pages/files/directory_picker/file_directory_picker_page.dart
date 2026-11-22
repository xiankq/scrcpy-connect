import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class FileDirectoryPickerPage extends HookConsumerWidget {
  const FileDirectoryPickerPage({
    super.key,
    required this.device,
    required this.initialPath,
  });
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
    final theme = Theme.of(context);
    final label = deviceName(device);
    final parent = fileParentPath(path.value);
    Future<void> refresh() => ref.read(provider.notifier).refresh();

    return PageFrame(
      titleStyle: Theme.of(context).textTheme.headlineMedium,
      title: '选择目标目录',
      bottom: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('文件将发送到', style: theme.textTheme.bodySmall),
            const SizedBox(height: DesignTokens.spacingXs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? DesignTokens.colorAccentBlueSoftDark
                    : DesignTokens.colorAccentBlueSoft,
                borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
              ),
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingSm),
                child: Text(
                  '$label · ${path.value}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            FilledButton(
              style: pagePrimaryButtonStyle,
              onPressed: query.verified
                  ? () => closePage<String>(context, path.value)
                  : null,
              child: const Text('使用此目录'),
            ),
          ],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverPadding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  if (parent != null) ...[
                    IconButton(
                      onPressed: () => path.value = parent,
                      tooltip: '上一级',
                      icon: const Icon(LucideIcons.arrowUp),
                    ),
                    const SizedBox(width: DesignTokens.spacingXs),
                  ],
                  Expanded(
                    child: FileBreadcrumbs(
                      path: path.value,
                      onSelected: (next) => path.value = next,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (query.data != null && query.error != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StateNote('无法核验当前目录。请刷新后再选择。'),
                    TextButton(onPressed: refresh, child: const Text('刷新目录')),
                  ],
                ),
              ),
            ),
          ContentArrival(
            sliver: true,
            state: query.data != null,
            waiting: query.loading && query.data == null,
            child: SliverMainAxisGroup(
              slivers: [
                if (query.data case final data?)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingMd,
                    ),
                    sliver: Builder(
                      builder: (context) {
                        final directories = data.entries
                            .where((entry) => entry.isDirectory)
                            .toList();
                        if (directories.isEmpty) {
                          return const SliverToBoxAdapter(
                            child: Text('此目录没有子文件夹'),
                          );
                        }
                        return SliverList.builder(
                          itemCount: directories.length,
                          itemBuilder: (context, index) {
                            final directory = directories[index];
                            return Material(
                              color: theme.colorScheme.surface,
                              child: ActionRow(
                                key: ValueKey(directory.path),
                                icon: LucideIcons.folder,
                                color: DesignTokens.colorListIconAmber,
                                title: directory.name,
                                onTap:
                                    !fileCanOpen(directory) || !query.verified
                                    ? null
                                    : () => path.value = directory.path!,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  )
                else
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AsyncContent(
                      loading: query.loading,
                      data: query.data,
                      error: query.error,
                      onRefresh: refresh,
                      emptyTitle: '无法读取这个文件夹',
                      failure: '请检查手机连接后重试。',
                      loadingPlaceholder: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        child: SkeletonRows(lines: 1, trailing: true),
                      ),
                      builder: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
