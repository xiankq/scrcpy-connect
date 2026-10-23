import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_entry_sliver.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_entry_tiles.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_selection_bar.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_type_filter_grid.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_view_menu.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_source_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/services/file_browser_model.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class FilesPage extends HookConsumerWidget {
  const FilesPage({
    super.key,
    required this.controller,
    required this.device,
    this.initialPath = '/sdcard',
  });

  final AppController controller;
  final Json device;
  final String initialPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final viewMode = _fileViewModeFromSettings(settings);
    final sortKey = _fileSortKeyFromSettings(settings);
    final ascending = _fileSortAscendingFromSettings(settings);
    final path = useState(initialPath);
    final revision = useState(0);
    final selected = useState<Set<String>>({});
    final busy = useState(false);
    final typeFilter = useState(FileTypeFilter.all);

    Future<bool> mutate(String command, Json params) async {
      busy.value = true;
      try {
        final result = await perform(context, controller, command, {
          'deviceId': device['id'],
          ...params,
        });
        if (context.mounted) {
          revision.value++;
          selected.value = {};
        }
        return result != null;
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    void openDirectory(String next) {
      if (next == path.value) return;
      path.value = next;
      typeFilter.value = FileTypeFilter.all;
      selected.value = {};
    }

    Future<void> updateBrowserPreferences(Json patch) async {
      try {
        await controller.updateSettings(patch);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      }
    }

    Future<void> upload() async {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !context.mounted) return;
      final items = [
        for (final file in picked)
          if (file.path != null)
            {'source': file.path, 'destination': '${path.value}/${file.name}'},
      ];
      if (items.isEmpty) {
        feedback(context, '所选文件没有可读取的本机路径，请从系统文件位置重新选择。');
        return;
      }
      final submitted = await mutate('files.push', {
        'items': items,
        'conflict': 'ask',
      });
      if (submitted && context.mounted) {
        TransferCenterRoute().push<void>(context);
      }
    }

    Future<void> uploadDirectory() async {
      final submitted = await DocumentImportRoute(
        deviceId: value(device, 'id'),
        destination: path.value,
      ).push<bool>(context);
      if (submitted == true && context.mounted) revision.value++;
    }

    Future<void> handleEntryAction(String action, Json entry) async {
      final entryPath = value(entry, 'path');
      final folder = entry['isDirectory'] == true;
      final manageable = fileCanManage(entry);
      final openable = fileCanOpen(entry);

      void toggle() {
        if (!manageable) return;
        final next = {...selected.value};
        next.contains(entryPath) ? next.remove(entryPath) : next.add(entryPath);
        selected.value = next;
      }

      switch (action) {
        case 'select':
          toggle();
        case 'rename':
          final name = await askText(
            context,
            title: '重命名',
            initial: value(entry, 'name'),
          );
          if (name != null && context.mounted) {
            if (name.contains('/') || name == '.' || name == '..') {
              feedback(context, '名称不能包含路径分隔符');
              return;
            }
            await mutate('files.rename', {'path': entryPath, 'name': name});
          }
        case 'delete':
          if (await confirm(
                context,
                '删除“${value(entry, 'name')}”？',
                '将从 ${deviceName(device)} 删除此${folder ? '文件夹及其内容' : '文件'}，无法在本应用撤销。',
                action: '删除',
                danger: true,
              ) &&
              context.mounted) {
            await mutate('files.delete', {
              'paths': [entryPath],
            });
          }
        case 'download':
          if (openable && context.mounted) {
            await retrieveFile(context, controller, device, entry);
          }
      }
    }

    final parentPath = fileParentPath(path.value);
    return PopScope(
      canPop: parentPath == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && parentPath != null) openDirectory(parentPath);
      },
      child: PageFrame(
        title: '文件管理',
        backgroundColor: Theme.of(context).colorScheme.surface,
        onBack: parentPath == null ? null : () => openDirectory(parentPath),
        actions: [
          GlassActionIcon(
            tooltip: '搜索文件',
            onPressed: () => FileSearchRoute(
              deviceId: value(device, 'id'),
              path: path.value,
            ).push<void>(context),
            icon: const Icon(LucideIcons.search),
          ),
          GlassActionIcon(
            tooltip: '新建文件夹',
            onPressed: busy.value
                ? null
                : () async {
                    final name = await askText(
                      context,
                      title: '新建文件夹',
                      label: '文件夹名称',
                      action: '创建',
                    );
                    if (name != null && context.mounted) {
                      if (name.contains('/') || name == '.' || name == '..') {
                        feedback(context, '文件夹名称不能包含路径分隔符');
                        return;
                      }
                      await mutate('files.mkdir', {
                        'path': '${path.value}/$name',
                      });
                    }
                  },
            icon: const Icon(LucideIcons.folderPlus),
          ),
          FileViewMenuButton(
            viewMode: viewMode,
            sortKey: sortKey,
            ascending: ascending,
            onViewModeChanged: (next) => unawaited(
              updateBrowserPreferences({'fileViewMode': next.name}),
            ),
            onSortKeyChanged: (next) =>
                unawaited(updateBrowserPreferences({'fileSortKey': next.name})),
            onAscendingChanged: (next) => unawaited(
              updateBrowserPreferences({'fileSortAscending': next}),
            ),
          ),
          GlassMenuButton(
            tooltip: '发送到手机',
            enabled: !busy.value && selected.value.isEmpty,
            icon: const Icon(LucideIcons.ellipsisVertical),
            actions: [
              GlassMenuAction(
                label: '发送本机文件',
                icon: const Icon(LucideIcons.upload),
                onPressed: busy.value ? null : upload,
              ),
              if (Platform.isAndroid ||
                  Platform.isLinux ||
                  Platform.isMacOS ||
                  Platform.isWindows)
                GlassMenuAction(
                  label: '发送本机文件夹',
                  icon: const Icon(LucideIcons.folderUp),
                  onPressed: busy.value ? null : uploadDirectory,
                ),
            ],
          ),
        ],
        child: CommandView(
          key: ValueKey(revision.value),
          controller: controller,
          command: 'files.list',
          params: {'deviceId': device['id'], 'path': path.value},
          emptyTitle: '无法读取这个目录',
          alternative: TextButton(
            onPressed: () =>
                openRemoteRoute(context, deviceId: value(device, 'id')),
            child: const Text('在手机上继续处理'),
          ),
          builder: (context, data, refresh) => HookBuilder(
            builder: (context) {
              final all = useMemoized(() => objects(data['entries']), [data]);
              final listing = useMemoized(
                () => buildDirectoryListing(
                  entries: all,
                  typeFilter: typeFilter.value,
                  sortKey: sortKey,
                  ascending: ascending,
                ),
                [all, typeFilter.value, sortKey, ascending],
              );
              final chosen = all
                  .where(
                    (entry) =>
                        fileCanManage(entry) &&
                        selected.value.contains(value(entry, 'path')),
                  )
                  .toList();
              final retrievable =
                  chosen.isNotEmpty && chosen.every(fileCanOpen);
              final atStorageRoot = path.value == '/sdcard';
              final hasFilter =
                  atStorageRoot && typeFilter.value != FileTypeFilter.all;
              final unavailableFiles =
                  listing.files.isEmpty &&
                  typeFilter.value != FileTypeFilter.all;

              Widget folderTile(Json folder, {required bool grid}) {
                final folderPath = value(folder, 'path');
                final manageable = fileCanManage(folder);
                final openable = fileCanOpen(folder);
                void onTap() {
                  if (selected.value.isNotEmpty) {
                    if (manageable) {
                      handleEntryAction('select', folder);
                    }
                  } else if (openable) {
                    openDirectory(folderPath);
                  }
                }

                final onLongPress = manageable
                    ? () => handleEntryAction('select', folder)
                    : null;
                final selectedFolder = selected.value.contains(folderPath);
                return grid
                    ? FolderGridTile(
                        key: ValueKey(folderPath),
                        folder: folder,
                        selected: selectedFolder,
                        selectionActive: selected.value.isNotEmpty,
                        onTap: onTap,
                        onLongPress: onLongPress,
                      )
                    : FolderListTile(
                        key: ValueKey(folderPath),
                        folder: folder,
                        selected: selectedFolder,
                        selectionActive: selected.value.isNotEmpty,
                        onTap: onTap,
                        onLongPress: onLongPress,
                      );
              }

              Widget fileTile(Json file, {required bool grid}) {
                final filePath = value(file, 'path');
                final manageable = fileCanManage(file);
                final openable = fileCanOpen(file);
                void onTap() {
                  if (selected.value.isNotEmpty) {
                    if (manageable) {
                      handleEntryAction('select', file);
                    }
                  } else if (openable) {
                    FileDetailsRoute(
                      deviceId: value(device, 'id'),
                      path: filePath,
                    ).push<void>(context);
                  }
                }

                final onLongPress = manageable
                    ? () => handleEntryAction('select', file)
                    : null;
                return grid
                    ? FileGridTile(
                        key: ValueKey(filePath),
                        controller: controller,
                        device: device,
                        file: file,
                        selected: selected.value.contains(filePath),
                        selectionActive: selected.value.isNotEmpty,
                        onTap: onTap,
                        onLongPress: onLongPress,
                      )
                    : FileListTile(
                        key: ValueKey(filePath),
                        file: file,
                        selected: selected.value.contains(filePath),
                        selectionActive: selected.value.isNotEmpty,
                        onTap: onTap,
                        onLongPress: onLongPress,
                      );
              }

              Widget entryTile(Json entry, {required bool grid}) =>
                  entry['isDirectory'] == true
                  ? folderTile(entry, grid: grid)
                  : fileTile(entry, grid: grid);

              return RefreshIndicator(
                onRefresh: () async {
                  selected.value = {};
                  refresh();
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const PageChromeSliver(),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          DesignTokens.spacingMd,
                          DesignTokens.spacingXs,
                          DesignTokens.spacingMd,
                          DesignTokens.spacingSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!atStorageRoot) ...[
                              DeviceSourceRow(
                                device: device,
                                padding: const EdgeInsets.only(
                                  bottom: DesignTokens.spacingSm,
                                ),
                              ),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: FileBreadcrumbs(
                                    path: path.value,
                                    onSelected: openDirectory,
                                  ),
                                ),
                                const SizedBox(width: DesignTokens.spacingXs),
                                GlassActionIcon(
                                  tooltip: '刷新目录',
                                  onPressed: busy.value
                                      ? null
                                      : () {
                                          selected.value = {};
                                          refresh();
                                        },
                                  icon: const Icon(LucideIcons.refreshCw),
                                  iconSize:
                                      DesignTokens.componentIconSmallSize +
                                      DesignTokens.spacingMicro,
                                  padding: EdgeInsets.zero,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  constraints: const BoxConstraints.tightFor(
                                    width:
                                        DesignTokens.componentSmallButtonSize,
                                    height:
                                        DesignTokens.componentSmallButtonSize,
                                  ),
                                ),
                              ],
                            ),
                            if (atStorageRoot) ...[
                              const SizedBox(height: DesignTokens.spacingMd),
                              FileTypeFilterGrid(
                                selected: typeFilter.value,
                                onSelected: (next) => typeFilter.value = next,
                              ),
                            ],
                            if (busy.value) ...[
                              const SizedBox(height: DesignTokens.spacingSm),
                              const LinearProgressIndicator(minHeight: 2),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (selected.value.isNotEmpty)
                      SliverToBoxAdapter(
                        child: FileSelectionBar(
                          count: chosen.length,
                          onRename: chosen.length == 1
                              ? () => handleEntryAction('rename', chosen.single)
                              : null,
                          onRetrieve: retrievable
                              ? () => retrieveSelection(
                                  context,
                                  controller,
                                  device,
                                  chosen,
                                )
                              : null,
                          onDelete: chosen.isEmpty
                              ? null
                              : () async {
                                  if (await confirm(
                                        context,
                                        '删除 ${chosen.length} 项？',
                                        '将从 ${deviceName(device)} 删除所选内容。此操作无法在本应用撤销，若结果未知请重新检查目录。',
                                        action: '删除',
                                        danger: true,
                                      ) &&
                                      context.mounted) {
                                    await mutate('files.delete', {
                                      'paths': chosen
                                          .map((entry) => entry['path'])
                                          .toList(),
                                    });
                                  }
                                },
                          onClear: () => selected.value = {},
                        ),
                      ),
                    if (listing.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyContent(
                          icon: hasFilter
                              ? LucideIcons.searchX
                              : LucideIcons.folderOpen,
                          title: hasFilter
                              ? '当前目录没有匹配内容'
                              : all.isEmpty
                              ? '这个目录是空的'
                              : '目录中没有可显示内容',
                          message: hasFilter
                              ? '文件类型只筛选当前目录中的文件；文件夹仍按原顺序显示。'
                              : '发送本机文件到 ${path.value}，或新建文件夹。',
                          action: TextButton(
                            onPressed: hasFilter
                                ? () => typeFilter.value = FileTypeFilter.all
                                : upload,
                            child: Text(hasFilter ? '清除筛选' : '发送文件'),
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        sliver: FileEntrySliver(
                          entries: listing.entries,
                          viewMode: viewMode,
                          builder: (entry, grid) =>
                              entryTile(entry, grid: grid),
                        ),
                      ),
                      if (unavailableFiles)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DesignTokens.spacingMd,
                              DesignTokens.spacingSm,
                              DesignTokens.spacingMd,
                              DesignTokens.spacingMd,
                            ),
                            child: StateNote(
                              '当前目录没有${_typeFilterLabel(typeFilter.value)}文件。'
                              '文件夹不受文件类型筛选影响。',
                              icon: LucideIcons.info,
                            ),
                          ),
                        ),
                    ],
                    const SliverToBoxAdapter(
                      child: SizedBox(height: DesignTokens.spacingLg),
                    ),
                    const PageChromeBottomSliver(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

String _typeFilterLabel(FileTypeFilter filter) => switch (filter) {
  FileTypeFilter.all => '全部',
  FileTypeFilter.documents => '文档',
  FileTypeFilter.images => '图片',
  FileTypeFilter.videos => '视频',
  FileTypeFilter.audio => '音频',
};

FileViewMode _fileViewModeFromSettings(Json settings) =>
    value(settings, 'fileViewMode') == 'list'
    ? FileViewMode.list
    : FileViewMode.grid;

FileSortKey _fileSortKeyFromSettings(Json settings) =>
    switch (value(settings, 'fileSortKey')) {
      'size' => FileSortKey.size,
      'modified' => FileSortKey.modified,
      'type' => FileSortKey.type,
      _ => FileSortKey.name,
    };

bool _fileSortAscendingFromSettings(Json settings) =>
    settings['fileSortAscending'] != false;
