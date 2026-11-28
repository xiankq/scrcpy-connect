import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/grouped_list_segment.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/router/navigation.dart';
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
    final label = deviceName(device);
    Future<void> refresh() => ref.read(provider.notifier).refresh();

    return PageFrame(
      title: '选择目标目录',
      bottom: AppButton(
        label: '使用此目录',
        role: AppButtonRole.primary,
        expand: true,
        onPressed: query.verified
            ? () => closePage<String>(context, path.value)
            : null,
      ),
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.componentPagePadding,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FileBreadcrumbs(
                    path: path.value,
                    onSelected: (next) => path.value = next,
                  ),
                  if (query.data != null && query.error != null) ...[
                    const StateNote('无法核验当前目录。请刷新后再选择。'),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton(
                        label: '刷新目录',
                        role: AppButtonRole.secondaryOnPage,
                        size: AppButtonSize.section,
                        onPressed: refresh,
                      ),
                    ),
                  ],
                  SectionTitle('${fileDirectoryLabel(path.value)} 中的文件夹'),
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
                      horizontal: DesignTokens.componentPagePadding,
                    ),
                    sliver: Builder(
                      builder: (context) {
                        final directories = data.entries
                            .where((entry) => entry.isDirectory)
                            .toList();
                        if (directories.isEmpty) {
                          return const SliverToBoxAdapter(
                            child: SectionFooter('此目录没有子文件夹'),
                          );
                        }
                        return SliverList.builder(
                          itemCount: directories.length,
                          itemBuilder: (context, index) {
                            final directory = directories[index];
                            final enabled =
                                fileCanOpen(directory) && query.verified;
                            return GroupedListSegment.at(
                              key: ValueKey(directory.path),
                              index: index,
                              count: directories.length,
                              separatorIndent: tileRowSeparatorIndent,
                              child: AppListRow(
                                leading: const ListIconBadge(
                                  icon: folderKindIcon,
                                  backgroundColor: folderKindColor,
                                ),
                                title: Text(directory.name),
                                chevron: true,
                                enabled: enabled,
                                onTap: !enabled
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
                          horizontal: DesignTokens.componentPagePadding,
                        ),
                        child: SkeletonRows(lines: 1, trailing: true),
                      ),
                      builder: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.componentPagePadding,
            ),
            sliver: SliverToBoxAdapter(
              child: SectionFooter('文件将发送到 $label · ${path.value}'),
            ),
          ),
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
