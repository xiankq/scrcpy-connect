import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/services/files/file_browser.dart';
import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:design_system/design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_entry_sliver.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_browser_entry.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_selection_bar.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_type_filter_grid.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_view_menu.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_source_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/file_actions.dart';
import 'package:scrcpy_connect/models/file_browser.dart';
import 'package:scrcpy_connect/widgets/command_query.dart';
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
    final selectionObjects = useRef<Map<String, Json>>({});
    final selecting = useState(false);
    final selectionMenu = useMemoized(MenuController.new);
    final loaded = useRef<List<Json>>([]);
    final sourceId = value(device, 'id');
    final live = ref.watch(
      appControllerProvider.select(
        (state) => (state.devices, state.reconciliationPending),
      ),
    );
    final currentDevice = live.$1
        .where((item) => item['id'] == sourceId)
        .firstOrNull;
    final connected = currentDevice?['status'] == 'connected' && !live.$2;
    final connectionRevision = useRef(0);
    final checkedRevision = useRef(-1);
    final query = useMemoized(
      () => CommandQuery(
        request: (command, [params = const {}]) async {
          final revision = connectionRevision.value;
          final result = await controller.request(command, params);
          final state = controller.snapshot();
          if (!state.reconciliationPending &&
              state.devices.any(
                (item) =>
                    item['id'] == sourceId && item['status'] == 'connected',
              )) {
            checkedRevision.value = revision;
          }
          return result;
        },
        events: controller.eventStream(),
        command: 'files.list',
        params: {'deviceId': sourceId, 'path': path.value},
      ),
      [controller, sourceId, path.value, revision.value],
    );
    useListenable(query);
    useEffect(() => query.dispose, [query]);
    final previousConnection = useRef(connected);
    useEffect(() {
      if (previousConnection.value != connected) {
        previousConnection.value = connected;
        connectionRevision.value++;
        unawaited(query.refresh());
      }
      return null;
    }, [query, connected]);
    final verified =
        connected &&
        checkedRevision.value == connectionRevision.value &&
        !query.loading &&
        query.error == null;
    bool selectionVerified() {
      final observed = {
        for (final entry in objects(query.data?['entries']))
          value(entry, 'path'): entry,
      };
      return selected.value.every((path) {
        final current = observed[path];
        final previous = selectionObjects.value[path];
        return current != null &&
            previous != null &&
            fileCanManage(current) &&
            _sameObservedFile(previous, current);
      });
    }

    bool canSubmit() {
      final state = controller.snapshot();
      final current = state.devices
          .where((item) => item['id'] == sourceId)
          .firstOrNull;
      return current?['status'] == 'connected' &&
          !state.reconciliationPending &&
          checkedRevision.value == connectionRevision.value &&
          !query.loading &&
          query.error == null &&
          query.data != null &&
          (!selecting.value || selectionVerified());
    }

    useEffect(() {
      selected.value = {};
      selectionObjects.value = {};
      loaded.value = [];
      selecting.value = false;
      return null;
    }, [sourceId]);
    final busy = useState(false);
    final typeFilter = useState(FileTypeFilter.all);

    Future<bool> mutate(String command, Json params) async {
      if (!canSubmit()) {
        feedback(context, '设备已断开或目录尚未重新核验，请重连后再试。');
        return false;
      }
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
      if (selecting.value || !verified || next == path.value) return;
      loaded.value = [];
      selectionObjects.value = {};
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
      if (!canSubmit()) return;
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
      if (Platform.isIOS || !canSubmit()) return;
      if (!Platform.isAndroid) {
        final source = await FilePicker.getDirectoryPath(
          dialogTitle: '选择发送的文件夹',
        );
        if (source == null || !context.mounted) return;
        final name = p.basename(p.normalize(source));
        if (name.isEmpty ||
            name == '.' ||
            p.equals(p.normalize(source), p.rootPrefix(source))) {
          feedback(context, '请选择有明确名称的文件夹');
          return;
        }
        final submitted = await mutate('files.push', {
          'items': [
            {'source': source, 'destination': p.posix.join(path.value, name)},
          ],
          'conflict': 'ask',
        });
        if (submitted && context.mounted) {
          TransferCenterRoute().push<void>(context);
        }
        return;
      }
      final submitted = await DocumentImportRoute(
        deviceId: value(device, 'id'),
        destination: path.value,
      ).push<bool>(context);
      if (submitted == true && context.mounted) revision.value++;
    }

    void toggleEntry(Json entry) {
      if (!fileCanManage(entry)) return;
      final entryPath = value(entry, 'path');
      selecting.value = true;
      final next = {...selected.value};
      if (next.contains(entryPath)) {
        next.remove(entryPath);
        selectionObjects.value.remove(entryPath);
      } else {
        next.add(entryPath);
        selectionObjects.value[entryPath] = Map.of(entry);
      }
      selected.value = next;
    }

    Future<void> renameEntry(Json entry) async {
      final name = await askText(
        context,
        title: '重命名',
        initial: value(entry, 'name'),
      );
      if (name == null || !context.mounted) return;
      if (name.contains('/') || name == '.' || name == '..') {
        feedback(context, '名称不能包含路径分隔符');
        return;
      }
      await mutate('files.rename', {
        'path': value(entry, 'path'),
        'name': name,
        'expectedStamp': entry['sourceStamp'],
      });
    }

    void exitSelection() {
      if (selectionMenu.isOpen) {
        selectionMenu.close();
        return;
      }
      selected.value = {};
      selecting.value = false;
    }

    final chosen = [
      for (final path in selected.value) ?selectionObjects.value[path],
    ];
    final visible = buildDirectoryListing(
      entries: loaded.value,
      typeFilter: typeFilter.value,
      sortKey: sortKey,
      ascending: ascending,
    ).entries.where(fileCanManage).toList();
    final allSelected =
        visible.isNotEmpty &&
        visible.every((entry) => selected.value.contains(value(entry, 'path')));
    final retrievable =
        verified &&
        selectionVerified() &&
        !busy.value &&
        chosen.isNotEmpty &&
        chosen.every(fileCanOpen);
    final parentPath = fileParentPath(path.value);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (selecting.value) exitSelection();
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !selecting.value && (parentPath == null || !connected),
          onPopInvokedWithResult: (popped, _) {
            if (popped) return;
            if (selecting.value) {
              exitSelection();
            } else if (parentPath != null) {
              openDirectory(parentPath);
            }
          },
          child: PageFrame(
            title: selecting.value ? '已选择 ${selected.value.length} 项' : '文件管理',
            leading: selecting.value
                ? GlassActionIcon(
                    tooltip: '退出选择',
                    onPressed: exitSelection,
                    icon: const Icon(LucideIcons.x),
                  )
                : null,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onBack: selecting.value
                ? exitSelection
                : parentPath == null || !connected
                ? null
                : () => openDirectory(parentPath),
            actions: selecting.value
                ? [
                    GlassActionIcon(
                      tooltip: allSelected ? '取消全选' : '全选',
                      onPressed: () {
                        selectionObjects.value = allSelected
                            ? {}
                            : {
                                for (final entry in visible)
                                  value(entry, 'path'): Map.of(entry),
                              };
                        selected.value = selectionObjects.value.keys.toSet();
                      },
                      icon: Icon(
                        allSelected
                            ? LucideIcons.listX
                            : LucideIcons.listChecks,
                      ),
                    ),
                  ]
                : [
                    GlassActionIcon(
                      tooltip: '搜索文件',
                      onPressed: !verified
                          ? null
                          : () => FileSearchRoute(
                              deviceId: sourceId,
                              path: path.value,
                            ).push<void>(context),
                      icon: const Icon(LucideIcons.search),
                    ),
                    FileViewMenuButton(
                      viewMode: viewMode,
                      sortKey: sortKey,
                      ascending: ascending,
                      onViewModeChanged: (next) => unawaited(
                        updateBrowserPreferences({'fileViewMode': next.name}),
                      ),
                      onSortKeyChanged: (next) => unawaited(
                        updateBrowserPreferences({'fileSortKey': next.name}),
                      ),
                      onAscendingChanged: (next) => unawaited(
                        updateBrowserPreferences({'fileSortAscending': next}),
                      ),
                    ),
                    GlassMenuButton(
                      tooltip: '更多文件操作',
                      icon: const Icon(LucideIcons.ellipsisVertical),
                      actions: [
                        GlassMenuAction(
                          label: '选择',
                          icon: const Icon(LucideIcons.squareCheck),
                          onPressed: () => selecting.value = true,
                        ),
                        GlassMenuAction(
                          label: '新建文件夹',
                          icon: const Icon(LucideIcons.folderPlus),
                          onPressed: busy.value || !verified
                              ? null
                              : () async {
                                  final name = await askText(
                                    context,
                                    title: '新建文件夹',
                                    label: '文件夹名称',
                                    action: '创建',
                                  );
                                  if (name == null || !context.mounted) return;
                                  if (name.isEmpty ||
                                      name.contains('/') ||
                                      name == '.' ||
                                      name == '..') {
                                    feedback(context, '文件夹名称不能包含路径分隔符');
                                    return;
                                  }
                                  await mutate('files.mkdir', {
                                    'path': '${path.value}/$name',
                                  });
                                },
                        ),
                        GlassMenuAction(
                          label: '发送本机文件',
                          icon: const Icon(LucideIcons.upload),
                          onPressed: busy.value || !verified ? null : upload,
                        ),
                        if (Platform.isAndroid || Platform.isLinux)
                          GlassMenuAction(
                            label: '发送本机文件夹',
                            icon: const Icon(LucideIcons.folderUp),
                            onPressed: busy.value || !verified
                                ? null
                                : uploadDirectory,
                          ),
                      ],
                    ),
                  ],
            bottomRadius: DesignTokens.roundedFull,
            bottom: selecting.value
                ? FileSelectionBar(
                    menuController: selectionMenu,
                    onRetrieve: retrievable
                        ? () => retrieveSelection(
                            context,
                            controller,
                            device,
                            chosen,
                            canSubmit: canSubmit,
                            canReduceSelection: true,
                          )
                        : null,
                    retrieveReason: !connected
                        ? '设备已断开，重连后才能取回原文件'
                        : !verified
                        ? '目录尚未重新核验，请先重新检查'
                        : !selectionVerified()
                        ? '部分所选项未在本次范围内核验，请重新选择当前条目'
                        : chosen.isEmpty
                        ? '请先选择文件'
                        : '所选内容暂不可取回',
                    onDelete:
                        !verified ||
                            !selectionVerified() ||
                            busy.value ||
                            chosen.isEmpty
                        ? null
                        : () async {
                            if (await confirm(
                                  context,
                                  '删除 ${chosen.length} 项？',
                                  '将从 ${deviceName(device)} 的 ${path.value} 删除所选内容。此操作无法在本应用撤销，若结果未知请重新检查目录。',
                                  action: '删除',
                                  danger: true,
                                ) &&
                                context.mounted) {
                              await mutate('files.delete', {
                                'paths': chosen
                                    .map((entry) => entry['path'])
                                    .toList(),
                                'expectedStamps': {
                                  for (final entry in chosen)
                                    value(entry, 'path'): entry['sourceStamp'],
                                },
                              });
                            }
                          },
                    deleteReason: !connected
                        ? '设备已断开，重连后才能删除'
                        : !selectionVerified()
                        ? '部分所选项未在本次范围内核验，请重新选择当前条目'
                        : '请先选择文件',
                    onRename:
                        verified &&
                            selectionVerified() &&
                            !busy.value &&
                            chosen.length == 1
                        ? () => renameEntry(chosen.single)
                        : null,
                    viewMode: viewMode,
                    onToggleView: () => unawaited(
                      updateBrowserPreferences({
                        'fileViewMode': viewMode == FileViewMode.grid
                            ? 'list'
                            : 'grid',
                      }),
                    ),
                  )
                : null,
            child: query.data == null
                ? PageChromeBody(
                    child: query.loading
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : EmptyContent(
                            icon: LucideIcons.folderX,
                            title: '无法读取这个目录',
                            message: '${query.error}',
                            action: TextButton(
                              onPressed: () => unawaited(query.refresh()),
                              child: const Text('重新检查'),
                            ),
                          ),
                  )
                : HookBuilder(
                    builder: (context) {
                      final data = query.data!;
                      void refresh() => unawaited(query.refresh());
                      final all = useMemoized(() => objects(data['entries']), [
                        data,
                      ]);
                      loaded.value = all;
                      useEffect(() {
                        if (!verified) return null;
                        final observed = {
                          for (final entry in all) value(entry, 'path'): entry,
                        };
                        final complete =
                            data['hasMore'] != true &&
                            data['truncated'] != true;
                        final invalid = selected.value.where((path) {
                          final entry = observed[path];
                          if (entry == null) return complete;
                          final previous = selectionObjects.value[path];
                          return !fileCanManage(entry) ||
                              previous != null &&
                                  !_sameObservedFile(previous, entry);
                        }).toSet();
                        if (invalid.isNotEmpty) {
                          scheduleMicrotask(() {
                            if (context.mounted) {
                              selected.value = selected.value.difference(
                                invalid,
                              );
                            }
                          });
                        }
                        return null;
                      }, [all, verified]);
                      final listing = useMemoized(
                        () => buildDirectoryListing(
                          entries: all,
                          typeFilter: typeFilter.value,
                          sortKey: sortKey,
                          ascending: ascending,
                        ),
                        [all, typeFilter.value, sortKey, ascending],
                      );
                      final atStorageRoot = path.value == '/sdcard';
                      final hasFilter =
                          atStorageRoot &&
                          typeFilter.value != FileTypeFilter.all;
                      final unavailableFiles =
                          listing.files.isEmpty &&
                          typeFilter.value != FileTypeFilter.all;

                      return RefreshIndicator(
                        onRefresh: () async {
                          if (!selecting.value) refresh();
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
                                    DeviceSourceRow(
                                      device: currentDevice ?? device,
                                      padding: const EdgeInsets.only(
                                        bottom: DesignTokens.spacingSm,
                                      ),
                                    ),
                                    if (!verified)
                                      StateNote(
                                        !connected
                                            ? '设备已断开，已保留当前目录与选择。重连并核验目录后才能提交操作。'
                                            : query.error != null
                                            ? '目录未能重新核验：${query.error}。当前显示上次内容，重新检查后才能提交操作。'
                                            : '正在重新核验目录，当前内容与选择继续保留…',
                                      ),
                                    if (verified && !selectionVerified())
                                      const StateNote(
                                        '部分所选项未出现在本次已核验范围，已保留选择并暂停批量操作。可重新全选当前已加载范围，或退出选择后刷新核验。',
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FileBreadcrumbs(
                                            path: path.value,
                                            onSelected: selecting.value
                                                ? null
                                                : openDirectory,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: DesignTokens.spacingXs,
                                        ),
                                        GlassActionIcon(
                                          tooltip: '刷新目录',
                                          onPressed:
                                              busy.value || selecting.value
                                              ? null
                                              : () {
                                                  selected.value = {};
                                                  refresh();
                                                },
                                          icon: const Icon(
                                            LucideIcons.refreshCw,
                                          ),
                                          iconSize:
                                              DesignTokens
                                                  .componentIconSmallSize +
                                              DesignTokens.spacingMicro,
                                          padding: EdgeInsets.zero,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: DesignTokens
                                                    .componentSmallButtonSize,
                                                height: DesignTokens
                                                    .componentSmallButtonSize,
                                              ),
                                        ),
                                      ],
                                    ),
                                    if (atStorageRoot) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacingMd,
                                      ),
                                      FileTypeFilterGrid(
                                        selected: typeFilter.value,
                                        onSelected: selecting.value
                                            ? null
                                            : (next) => typeFilter.value = next,
                                      ),
                                    ],
                                    if (data['hasMore'] == true ||
                                        data['truncated'] == true)
                                      StateNote(
                                        '当前已加载 ${all.length} 项${data['total'] is num ? '，已知共 ${data['total']} 项' : ''}；仅操作已加载范围，未检查内容不纳入全选。',
                                      ),
                                    if (busy.value) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacingSm,
                                      ),
                                      const LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    ],
                                  ],
                                ),
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
                                    onPressed: selecting.value || !verified
                                        ? null
                                        : hasFilter
                                        ? () => typeFilter.value =
                                              FileTypeFilter.all
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
                                  builder: (entry, grid) => FileBrowserEntry(
                                    key: ValueKey(value(entry, 'path')),
                                    controller: controller,
                                    device: device,
                                    entry: entry,
                                    grid: grid,
                                    selected: selected.value.contains(
                                      value(entry, 'path'),
                                    ),
                                    selectionActive: selecting.value,
                                    enabled: verified,
                                    onBeginSelect: (entry) {
                                      selecting.value = true;
                                      selectionObjects.value.putIfAbsent(
                                        value(entry, 'path'),
                                        () => Map.of(entry),
                                      );
                                      selected.value = {
                                        ...selected.value,
                                        value(entry, 'path'),
                                      };
                                    },
                                    onSelect: toggleEntry,
                                    onOpenDirectory: openDirectory,
                                  ),
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
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: selecting.value
                                    ? MediaQuery.textScalerOf(context).scale(
                                            DesignTokens
                                                .componentNavigationHeight,
                                          ) +
                                          DesignTokens.spacingXxl +
                                          MediaQuery.paddingOf(context).bottom
                                    : DesignTokens.spacingLg,
                              ),
                            ),
                            const PageChromeBottomSliver(),
                          ],
                        ),
                      );
                    },
                  ),
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

bool _sameObservedFile(Json previous, Json current) => const [
  'sourceIdentity',
  'mode',
  'size',
  'modifiedSeconds',
  'modified',
  'kind',
  'isDirectory',
].every((key) => previous[key] == current[key]);
