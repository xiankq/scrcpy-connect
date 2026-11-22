import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/files/file_actions_notifier.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_browser_entry.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_entry_sliver.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_selection_bar.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_type_filter_grid.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_view_menu.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_source_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class FilesPage extends HookConsumerWidget {
  const FilesPage({
    super.key,
    required this.device,
    this.initialPath = '/sdcard',
  });

  final DeviceSnapshot device;
  final String initialPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    final viewMode = settings.fileViewMode;
    final sortKey = settings.fileSortKey;
    final ascending = settings.fileSortAscending;
    final path = useState(initialPath);
    final selected = useState<Map<String, FileCatalogEntry>>({});
    final selecting = useState(false);
    final selectionMenu = useMemoized(MenuController.new);
    final sourceId = device.id;
    final directorySource = ref.watch(fileDirectoriesProvider);
    final mutations = ref.watch(fileMutationsProvider);
    final transfers = ref.watch(fileTransfersProvider);
    final owner = useMemoized(Object.new, [
      directorySource,
      mutations,
      transfers,
      device.id,
      device.guid,
      device.serial,
      path.value,
    ]);
    final currentOwner = useRef(owner)..value = owner;
    bool ownsView() => context.mounted && identical(currentOwner.value, owner);
    final currentDevice = ref.watch(
      deviceListProvider.select(
        (state) =>
            state.devices.where((item) => item.id == sourceId).firstOrNull,
      ),
    );
    final connected = ref.watch(deviceReadinessProvider(sourceId)).ready;
    final queryProvider = fileDirectoryProvider((
      deviceId: sourceId,
      path: path.value,
    ));
    final query = ref.watch(queryProvider);
    Future<void> refresh() => ref.read(queryProvider.notifier).refresh();
    final verified = connected && query.verified;
    bool selectionVerified() {
      final observed = {
        for (final entry in query.data?.entries ?? const <FileCatalogEntry>[])
          (entry.path ?? ''): entry,
      };
      return selected.value.keys.every((path) {
        final current = observed[path];
        final previous = selected.value[path];
        return current != null &&
            previous != null &&
            fileCanManage(current) &&
            _sameObservedFile(previous, current);
      });
    }

    bool canSubmit() {
      if (!ownsView() ||
          !identical(ref.read(fileDirectoriesProvider), directorySource) ||
          !identical(ref.read(fileMutationsProvider), mutations) ||
          !identical(ref.read(fileTransfersProvider), transfers)) {
        return false;
      }
      return ref.read(deviceReadinessProvider(sourceId)).ready &&
          ref.read(queryProvider).verified &&
          (!selecting.value || selectionVerified());
    }

    useEffect(() {
      selected.value = {};
      selecting.value = false;
      return null;
    }, [owner]);
    final actionScope = useMemoized(Object.new);
    final actionsProvider = fileActionsProvider((
      deviceId: sourceId,
      path: path.value,
    ), scope: actionScope);
    final actionState = ref.watch(actionsProvider);
    final actions = ref.read(actionsProvider.notifier);
    ref.listen(actionsProvider, (_, next) {
      if (next.error case final error?) feedback(context, error);
    });
    final busy = actionState.busy;
    final typeFilter = useState(FileTypeFilter.all);

    Future<bool> mutate(Future<bool> Function() action) async {
      if (!ownsView()) return false;
      if (!canSubmit()) {
        feedback(context, '请确认手机已连接，再刷新这个文件夹。');
        return false;
      }
      final completed = await action();
      if (!ownsView()) return false;
      if (completed) selected.value = {};
      return completed;
    }

    void openDirectory(String next) {
      if (selecting.value || !verified || next == path.value) return;
      path.value = next;
      typeFilter.value = FileTypeFilter.all;
      selected.value = {};
    }

    Future<void> updateBrowserPreferences(PreferenceChanges patch) async {
      try {
        await ref.read(preferencesProvider.notifier).update(patch);
      } catch (error) {
        if (context.mounted) {
          feedback(
            context,
            failureMessage(error, fallback: '无法打开这个位置。请检查手机连接后重试。'),
          );
        }
      }
    }

    Future<void> upload() async {
      if (!canSubmit()) return;
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !context.mounted) return;
      final items = [
        for (final file in picked)
          if (file.path != null)
            FileTransferSelection(
              source: file.path!,
              destination: '${path.value}/${file.name}',
            ),
      ];
      if (items.isEmpty) {
        feedback(context, '无法读取所选文件。请在系统文件选择器中重新选择。');
        return;
      }
      final submitted = await mutate(() => actions.send(items));
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
          feedback(context, '请选择一个有名称的文件夹。');
          return;
        }
        final submitted = await mutate(
          () => actions.send([
            FileTransferSelection(
              source: source,
              destination: p.posix.join(path.value, name),
            ),
          ]),
        );
        if (submitted && context.mounted) {
          TransferCenterRoute().push<void>(context);
        }
        return;
      }
      await DocumentImportRoute(
        deviceId: device.id,
        destination: path.value,
      ).push<bool>(context);
    }

    void toggleEntry(FileCatalogEntry entry) {
      if (!fileCanManage(entry)) return;
      final entryPath = (entry.path ?? '');
      selecting.value = true;
      final next = Map.of(selected.value);
      if (next.containsKey(entryPath)) {
        next.remove(entryPath);
      } else {
        next[entryPath] = entry;
      }
      selected.value = next;
    }

    Future<void> renameEntry(FileCatalogEntry entry) async {
      final name = await askText(context, title: '重命名', initial: entry.name);
      if (name == null || !context.mounted) return;
      if (name.isEmpty || name.contains('/') || name == '.' || name == '..') {
        feedback(context, r'名称里不能使用 / 或 \');
        return;
      }
      if (entry case FileCatalogEntry(
        path: final path?,
        sourceStamp: final expected?,
      )) {
        await mutate(
          () => actions.rename((path: path, expected: expected), name),
        );
      } else if (ownsView()) {
        feedback(context, '无法找到所选文件。请刷新列表后重新选择。');
      }
    }

    void exitSelection() {
      if (selectionMenu.isOpen) {
        selectionMenu.close();
        return;
      }
      selected.value = {};
      selecting.value = false;
    }

    final data = query.data;

    final all = data?.entries ?? const <FileCatalogEntry>[];
    useEffect(() {
      if (!verified || data == null) return null;
      final observed = {for (final entry in all) (entry.path ?? ''): entry};
      final complete = !data.hasMore && !data.truncated;
      final invalid = selected.value.keys.where((path) {
        final entry = observed[path];
        if (entry == null) return complete;
        final previous = selected.value[path];
        return !fileCanManage(entry) ||
            previous != null && !_sameObservedFile(previous, entry);
      }).toSet();
      if (invalid.isNotEmpty) {
        scheduleMicrotask(() {
          if (context.mounted) {
            selected.value = Map.of(selected.value)
              ..removeWhere((path, _) => invalid.contains(path));
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
    final hasFilter = atStorageRoot && typeFilter.value != FileTypeFilter.all;
    final unavailableFiles =
        listing.files.isEmpty && typeFilter.value != FileTypeFilter.all;

    final chosen = selected.value.values.toList();
    final visible = listing.entries.where(fileCanManage).toList();
    final allSelected =
        visible.isNotEmpty &&
        visible.every(
          (entry) => selected.value.containsKey((entry.path ?? '')),
        );
    final retrievable =
        verified &&
        selectionVerified() &&
        !busy &&
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
            title: selecting.value
                ? '已选择 ${selected.value.length} 项'
                : atStorageRoot
                ? '文件'
                : p.posix.basename(path.value),
            leading: selecting.value
                ? Tooltip(
                    message: '退出选择',
                    child: GlassToolbarIconButton(
                      semanticLabel: '退出选择',
                      onPressed: exitSelection,
                      icon: const Icon(AppIcons.close),
                    ),
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
                        selected.value = allSelected
                            ? {}
                            : {
                                for (final entry in visible)
                                  (entry.path ?? ''): entry,
                              };
                      },
                      icon: Icon(
                        allSelected ? AppIcons.deselectAll : AppIcons.selectAll,
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
                      icon: const Icon(AppIcons.search),
                    ),
                  ],
            bottomGlass: false,
            bottom: selecting.value
                ? FileSelectionBar(
                    menuController: selectionMenu,
                    onRetrieve: retrievable
                        ? () => retrieveSelection(
                            context,
                            ref,
                            device,
                            chosen
                                .map(
                                  (file) => (
                                    path: file.path,
                                    name: file.name,
                                    canOpen: fileCanOpen(file),
                                  ),
                                )
                                .toList(),
                            canSubmit: canSubmit,
                            canReduceSelection: true,
                          )
                        : null,
                    retrieveReason: !connected
                        ? '设备已断开，重连后才能取回原文件'
                        : !verified
                        ? '请先刷新这个文件夹'
                        : !selectionVerified()
                        ? '部分选中的文件已找不到，请重新选择'
                        : chosen.isEmpty
                        ? '请先选择文件'
                        : '所选内容暂不可取回',
                    onDelete:
                        !verified ||
                            !selectionVerified() ||
                            busy ||
                            chosen.isEmpty
                        ? null
                        : () async {
                            if (await confirm(
                                  context,
                                  '删除 ${chosen.length} 项？',
                                  '将从 ${deviceName(device)} 的 ${path.value} 删除所选内容。',
                                  action: '同意',
                                  danger: true,
                                ) &&
                                context.mounted) {
                              final sources = <FileMutationSelection>[
                                for (final entry in chosen)
                                  if (entry case FileCatalogEntry(
                                    path: final path?,
                                    sourceStamp: final expected?,
                                  ))
                                    (path: path, expected: expected),
                              ];
                              if (sources.length != chosen.length) {
                                if (ownsView()) {
                                  feedback(context, '无法找到所选文件。请刷新列表后重新选择。');
                                }
                                return;
                              }
                              await mutate(() => actions.delete(sources));
                            }
                          },
                    deleteReason: !connected
                        ? '设备已断开，重连后才能删除'
                        : !selectionVerified()
                        ? '部分选中的文件已找不到，请重新选择'
                        : '请先选择文件',
                    onRename:
                        verified &&
                            selectionVerified() &&
                            !busy &&
                            chosen.length == 1
                        ? () => renameEntry(chosen.single)
                        : null,
                    viewMode: viewMode,
                    onToggleView: () => unawaited(
                      updateBrowserPreferences(
                        PreferenceChanges(
                          fileViewMode: viewMode == FileViewMode.grid
                              ? FileViewMode.list
                              : FileViewMode.grid,
                        ),
                      ),
                    ),
                  )
                : GlassActionBar(
                    actions: [
                      GlassMenuButton(
                        label: '发送',
                        tooltip: '发送到手机',
                        icon: const Icon(AppIcons.send),
                        enabled: !busy && verified,
                        actions: [
                          GlassMenuAction(
                            label: '发送本机文件',
                            icon: const Icon(AppIcons.send),
                            onPressed: upload,
                          ),
                          if (Platform.isAndroid || Platform.isLinux)
                            GlassMenuAction(
                              label: '发送本机文件夹',
                              icon: const Icon(LucideIcons.folderUp),
                              onPressed: uploadDirectory,
                            ),
                        ],
                      ),
                      FileViewMenuButton(
                        viewMode: viewMode,
                        sortKey: sortKey,
                        ascending: ascending,
                        onViewModeChanged: (next) => unawaited(
                          updateBrowserPreferences(
                            PreferenceChanges(fileViewMode: next),
                          ),
                        ),
                        onSortKeyChanged: (next) => unawaited(
                          updateBrowserPreferences(
                            PreferenceChanges(fileSortKey: next),
                          ),
                        ),
                        onAscendingChanged: (next) => unawaited(
                          updateBrowserPreferences(
                            PreferenceChanges(fileSortAscending: next),
                          ),
                        ),
                      ),
                      GlassMenuButton(
                        label: '更多',
                        tooltip: '更多文件操作',
                        icon: const Icon(AppIcons.more),
                        actions: [
                          GlassMenuAction(
                            label: '选择',
                            icon: const Icon(AppIcons.selectMode),
                            onPressed: () => selecting.value = true,
                          ),
                          GlassMenuAction(
                            label: '新建文件夹',
                            icon: const Icon(LucideIcons.folderPlus),
                            onPressed: busy || !verified
                                ? null
                                : () async {
                                    final name = await askText(
                                      context,
                                      title: '新建文件夹',
                                      label: '文件夹名称',
                                      action: '创建',
                                    );
                                    if (name == null || !context.mounted) {
                                      return;
                                    }
                                    if (name.isEmpty ||
                                        name.contains('/') ||
                                        name == '.' ||
                                        name == '..') {
                                      feedback(context, r'文件夹名称里不能使用 / 或 \');
                                      return;
                                    }
                                    await mutate(
                                      () => actions.createDirectory(name),
                                    );
                                  },
                          ),
                          GlassMenuAction(
                            label: '刷新',
                            icon: const Icon(AppIcons.refresh),
                            onPressed: busy ? null : refresh,
                          ),
                        ],
                      ),
                    ],
                  ),
            child: data == null && !query.loading
                ? PageChromeBody(
                    child: EmptyContent(
                      icon: LucideIcons.folderX,
                      title: '无法读取这个目录',
                      message: failureMessage(
                        query.error,
                        fallback: '无法读取这个文件夹。请检查手机连接后重试。',
                      ),
                      action: TextButton(
                        onPressed: () => unawaited(refresh()),
                        child: const Text('重新检查'),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      if (!selecting.value) await refresh();
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
                                if (!connected)
                                  DeviceSourceRow(
                                    device: currentDevice ?? device,
                                    padding: const EdgeInsets.only(
                                      bottom: DesignTokens.spacingSm,
                                    ),
                                  ),
                                if (data != null && !verified)
                                  StateNote(
                                    !connected
                                        ? '手机已断开。已保留当前文件和选择，重新连接并刷新后可继续操作。'
                                        : query.error != null
                                        ? '无法刷新文件夹。这里显示的是上次读取的内容。请刷新后再操作。'
                                        : '正在刷新文件夹，当前选择会保留。',
                                  ),
                                if (verified && !selectionVerified())
                                  const StateNote(
                                    '部分选中的文件已找不到。请重新全选当前列表，或退出选择后刷新。',
                                  ),
                                if (!atStorageRoot)
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
                                        onPressed: busy || selecting.value
                                            ? null
                                            : () {
                                                selected.value = {};
                                                refresh();
                                              },
                                        icon: const Icon(AppIcons.refresh),
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
                                  FileTypeFilterGrid(
                                    selected: typeFilter.value,
                                    onSelected: selecting.value
                                        ? null
                                        : (next) => typeFilter.value = next,
                                  ),
                                  const SizedBox(
                                    height: DesignTokens.spacingMd,
                                  ),
                                  Text(
                                    '手机存储',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ],
                                if (data != null &&
                                    (data.hasMore || data.truncated))
                                  StateNote(
                                    '当前已加载 ${all.length} 项${data.total == null ? '' : '，已知共 ${data.total} 项'}；仅操作已加载范围，未检查内容不纳入全选。',
                                  ),
                                if (busy) ...[
                                  const SizedBox(
                                    height: DesignTokens.spacingSm,
                                  ),
                                  const ContentLoadingIndicator(),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (data == null)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingMd,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: viewMode == FileViewMode.list
                                  ? SkeletonRows(
                                      key: ValueKey(path.value),
                                      trailing: true,
                                    )
                                  : LoadingSkeleton(
                                      key: ValueKey(path.value),
                                      child: _FileGridSkeleton(
                                        columns: fileGridColumnCount(context),
                                      ),
                                    ),
                            ),
                          )
                        else if (listing.isEmpty)
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
                                    ? () =>
                                          typeFilter.value = FileTypeFilter.all
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
                                key: ValueKey((entry.path ?? '')),
                                device: device,
                                entry: entry,
                                grid: grid,
                                selected: selected.value.containsKey(
                                  (entry.path ?? ''),
                                ),
                                selectionActive: selecting.value,
                                enabled: verified,
                                onBeginSelect: (entry) {
                                  selecting.value = true;
                                  final entryPath = (entry.path ?? '');
                                  selected.value = {
                                    ...selected.value,
                                    entryPath:
                                        selected.value[entryPath] ?? entry,
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
                                        DesignTokens.componentNavigationHeight,
                                      ) +
                                      DesignTokens.spacingXxl +
                                      MediaQuery.paddingOf(context).bottom
                                : DesignTokens.spacingLg,
                          ),
                        ),
                        const PageChromeBottomSliver(),
                      ],
                    ),
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

bool _sameObservedFile(FileCatalogEntry previous, FileCatalogEntry current) {
  Object observed(FileCatalogEntry entry) => (
    identity: entry.sourceIdentity,
    mode: entry.mode,
    size: entry.size,
    modifiedSeconds: entry.modifiedSeconds,
    modified: entry.modified,
    kind: entry.kind,
    directory: entry.isDirectory,
  );
  return observed(previous) == observed(current);
}

class _FileGridSkeleton extends StatelessWidget {
  const _FileGridSkeleton({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row < 4; row++) ...[
        if (row > 0) const SizedBox(height: DesignTokens.spacingSm),
        Row(
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: DesignTokens.spacingSm),
              const Expanded(
                child: Column(
                  children: [
                    AspectRatio(aspectRatio: 1, child: SkeletonBlock()),
                    SizedBox(height: DesignTokens.spacingXs),
                    SkeletonLine(fraction: 0.65, alignment: Alignment.center),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    ],
  );
}
