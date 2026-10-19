import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/file_row_title.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';

class FilesPage extends HookWidget {
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
  Widget build(BuildContext context) {
    final path = useState(initialPath);
    final query = useTextEditingController();
    useListenable(query);
    final revision = useState(0);
    final selected = useState<Set<String>>({});
    final busy = useState(false);
    Future<void> mutate(String command, Json params) async {
      busy.value = true;
      await perform(context, controller, command, {
        'deviceId': device['id'],
        ...params,
      });
      if (context.mounted) {
        revision.value++;
        busy.value = false;
        selected.value = {};
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
      final result = await perform(context, controller, 'files.push', {
        'deviceId': device['id'],
        'items': items,
        'conflict': 'ask',
      });
      if (result != null && context.mounted) {
        revision.value++;
        TransferCenterRoute().push<void>(context);
      }
    }

    Future<void> uploadDirectory() async {
      busy.value = true;
      try {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: '选择发送到设备的文件夹',
        );
        if (directory == null || !context.mounted) return;
        final parts = directory
            .split(RegExp(r'[/\\]'))
            .where((p) => p.isNotEmpty);
        if (parts.isEmpty) {
          feedback(context, '请选择具体文件夹，不能发送整个文件系统根目录。');
          return;
        }
        final destination = '${path.value}/${parts.last}';
        if (!await confirm(
              context,
              '发送整个文件夹？',
              '将“${parts.last}”及其内容发送到 ${deviceName(device)} 的 $destination。保留目录结构与空目录，同名内容逐项确认；符号链接不会跟随。',
              action: '发送文件夹',
            ) ||
            !context.mounted) {
          return;
        }
        final result = await perform(context, controller, 'files.push', {
          'deviceId': device['id'],
          'items': [
            {'source': directory, 'destination': destination},
          ],
          'conflict': 'ask',
        });
        if (result != null && context.mounted) {
          revision.value++;
          TransferCenterRoute().push<void>(context);
        }
      } catch (error) {
        if (context.mounted) feedback(context, '无法读取所选文件夹：$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PageFrame(
      title: '文件管理',

      actions: [
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
        GlassActionIcon(
          tooltip: '发送本机文件',
          onPressed: busy.value ? null : upload,
          icon: const Icon(LucideIcons.upload),
        ),
        if (Platform.isAndroid ||
            Platform.isLinux ||
            Platform.isMacOS ||
            Platform.isWindows)
          GlassActionIcon(
            tooltip: '发送本机文件夹',
            onPressed: busy.value
                ? null
                : Platform.isAndroid
                ? () async {
                    final submitted = await DocumentImportRoute(
                      deviceId: value(device, 'id'),
                      destination: path.value,
                    ).push<bool>(context);
                    if (submitted == true && context.mounted) revision.value++;
                  }
                : uploadDirectory,
            icon: const Icon(LucideIcons.folderUp),
          ),
      ],
      child: Builder(
        builder: (context) => NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
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
                  children: [
                    Row(
                      children: [
                        GlassActionIcon(
                          tooltip: '上一级目录',
                          onPressed: path.value == '/'
                              ? null
                              : () {
                                  final parent = path.value.substring(
                                    0,
                                    path.value.lastIndexOf('/'),
                                  );
                                  path.value = parent.isEmpty ? '/' : parent;
                                  selected.value = {};
                                },
                          icon: const Icon(
                            LucideIcons.arrowUp,
                            size: DesignTokens.componentIconActionSize,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            path.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        GlassActionIcon(
                          tooltip: '刷新目录',
                          onPressed: () => revision.value++,
                          icon: const Icon(
                            LucideIcons.refreshCw,
                            size: DesignTokens.componentIconActionSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: query,
                            decoration: const InputDecoration(
                              hintText: '搜索当前目录',
                              prefixIcon: Icon(
                                LucideIcons.search,
                                size: DesignTokens.componentIconActionSize,
                              ),
                            ),
                          ),
                        ),
                        GlassActionIcon(
                          tooltip: '搜索子文件夹',
                          onPressed: () => FileSearchRoute(
                            deviceId: value(device, 'id'),
                            path: path.value,
                            query: query.text,
                          ).push<void>(context),
                          icon: const Icon(
                            LucideIcons.folderSearch,
                            size: DesignTokens.componentIconActionSize,
                          ),
                        ),
                      ],
                    ),
                    if (busy.value) const LinearProgressIndicator(minHeight: 2),
                  ],
                ),
              ),
            ),
          ],
          body: PageChromePadding.removeTop(
            context: context,
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
              builder: (context, data, refresh) {
                final all = objects(data['entries']);
                final entries =
                    all
                        .where(
                          (e) => value(
                            e,
                            'name',
                          ).toLowerCase().contains(query.text.toLowerCase()),
                        )
                        .toList()
                      ..sort((a, b) {
                        if ((a['isDirectory'] == true) !=
                            (b['isDirectory'] == true)) {
                          return a['isDirectory'] == true ? -1 : 1;
                        }
                        return value(a, 'name').compareTo(value(b, 'name'));
                      });
                if (entries.isEmpty) {
                  return PageChromeBody(
                    child: EmptyContent(
                      icon: LucideIcons.folderOpen,
                      title: query.text.isEmpty ? '这个目录是空的' : '没有匹配的文件',
                      message: query.text.isEmpty
                          ? '发送本机文件到 ${path.value}，或新建文件夹。'
                          : '试试其他文件名。',
                      action: TextButton(
                        onPressed: query.text.isEmpty ? upload : query.clear,
                        child: Text(query.text.isEmpty ? '发送文件' : '清除搜索'),
                      ),
                    ),
                  );
                }
                final chosen = all
                    .where(
                      (e) =>
                          fileCanManage(e) &&
                          selected.value.contains(value(e, 'path')),
                    )
                    .toList();
                return Column(
                  children: [
                    if (selected.value.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('已选择 ${selected.value.length} 项'),
                            ),
                            GlassActionIcon(
                              tooltip: '取回所选',
                              onPressed: () async {
                                await retrieveSelection(
                                  context,
                                  controller,
                                  device,
                                  chosen,
                                );
                              },
                              icon: const Icon(LucideIcons.download),
                            ),
                            GlassActionIcon(
                              tooltip: '删除所选',
                              onPressed: () async {
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
                                        .map((e) => e['path'])
                                        .toList(),
                                  });
                                }
                              },
                              icon: const Icon(
                                LucideIcons.trash2,
                                color: ConnectTokens.danger,
                              ),
                            ),
                            GlassActionIcon(
                              tooltip: '取消选择',
                              onPressed: () => selected.value = {},
                              icon: const Icon(LucideIcons.x),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => refresh(),
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            DesignTokens.spacingMd,
                            0,
                            DesignTokens.spacingMd,
                            DesignTokens.spacingMd +
                                PageChromePadding.of(context).bottom,
                          ),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox.shrink(),
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            final entryPath = value(entry, 'path');
                            final folder = entry['isDirectory'] == true;
                            final openable = fileCanOpen(entry);
                            final manageable = fileCanManage(entry);
                            void toggle() {
                              if (!manageable) return;
                              final next = {...selected.value};
                              next.contains(entryPath)
                                  ? next.remove(entryPath)
                                  : next.add(entryPath);
                              selected.value = next;
                            }

                            Future<void> handleFileAction(String action) async {
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
                                    if (name.contains('/') ||
                                        name == '.' ||
                                        name == '..') {
                                      feedback(context, '名称不能包含路径分隔符');
                                      return;
                                    }
                                    await mutate('files.rename', {
                                      'path': entryPath,
                                      'name': name,
                                    });
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
                                  if (context.mounted) {
                                    await retrieveFile(
                                      context,
                                      controller,
                                      device,
                                      entry,
                                    );
                                  }
                              }
                            }

                            return GroupedItem(
                              index: i,
                              count: entries.length,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    leading: selected.value.isNotEmpty
                                        ? Checkbox(
                                            value: selected.value.contains(
                                              entryPath,
                                            ),
                                            onChanged: manageable
                                                ? (_) => toggle()
                                                : null,
                                          )
                                        : ListIconBadge(
                                            icon: folder
                                                ? LucideIcons.folder
                                                : LucideIcons.file,
                                            backgroundColor:
                                                DesignTokens.colorListIconAmber,
                                          ),
                                    title: FileRowTitle(
                                      tooltipTriggerMode:
                                          TooltipTriggerMode.manual,
                                      name: value(entry, 'name'),
                                      path: value(entry, 'path'),
                                      size: folder
                                          ? null
                                          : bytes(entry['size']),
                                    ),

                                    onLongPress: manageable ? toggle : null,
                                    onTap: !openable && !manageable
                                        ? null
                                        : () {
                                            if (selected.value.isNotEmpty) {
                                              toggle();
                                            } else if (folder && openable) {
                                              path.value = entryPath;
                                              query.clear();
                                            } else if (openable) {
                                              FileDetailsRoute(
                                                deviceId: value(device, 'id'),
                                                path: value(entry, 'path'),
                                              ).push<void>(context);
                                            }
                                          },
                                    trailing: GlassMenuButton(
                                      icon: const Icon(
                                        LucideIcons.ellipsisVertical,
                                      ),
                                      tooltip: '文件操作',
                                      enabled: openable || manageable,
                                      actions: [
                                        GlassMenuAction(
                                          label: '选择',
                                          onPressed: manageable
                                              ? () => handleFileAction('select')
                                              : null,
                                        ),
                                        GlassMenuAction(
                                          label: '重命名',
                                          onPressed: manageable
                                              ? () => handleFileAction('rename')
                                              : null,
                                        ),
                                        GlassMenuAction(
                                          label: '取回本机',
                                          onPressed: openable
                                              ? () =>
                                                    handleFileAction('download')
                                              : null,
                                        ),
                                        GlassMenuAction(
                                          label: '删除',
                                          destructive: true,
                                          onPressed: manageable
                                              ? () => handleFileAction('delete')
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!openable && !manageable)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: DesignTokens.spacingMd,
                                      ),
                                      child: StateNote(
                                        fileUnavailableReason(entry),
                                        icon: LucideIcons.circleAlert,
                                      ),
                                    ),
                                ],
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
          ),
        ),
      ),
    );
  }
}
