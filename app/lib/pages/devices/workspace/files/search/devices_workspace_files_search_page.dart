import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/file_row_title.dart';
import 'package:design_system/design_system.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/services/file_search_operation.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

const _filters = {
  'all': '全部',
  'images': '图片',
  'videos': '视频',
  'audio': '音频',
  'documents': '文档',
  'archives': '压缩包',
  'folders': '文件夹',
};

class FileSearchPage extends HookWidget {
  const FileSearchPage({
    super.key,
    required this.controller,
    required this.device,
    this.initialPath = '/sdcard',
    this.initialQuery = '',
  });
  final AppController controller;
  final Json device;
  final String initialPath;
  final String initialQuery;

  @override
  Widget build(BuildContext context) {
    final query = useTextEditingController(text: initialQuery);
    useListenable(query);
    final filter = useState('all');
    final entireStorage = useState(false);
    final root = entireStorage.value ? '/sdcard' : initialPath;
    final operation = useMemoized(
      () => FileSearchOperation(controller, value(device, 'id'), root),
      [controller, device['id'], root],
    );
    useEffect(() => operation.dispose, [operation]);
    useListenable(operation);
    final result = operation.result;
    final entries = objects(result?['entries']);
    final issues = objects(result?['issues']);
    final status = value(result ?? {}, 'status');
    final scopeExpanded = useMemoized(() => ValueNotifier(issues.isNotEmpty), [
      operation,
      status,
      issues.length,
    ]);
    useEffect(() => scopeExpanded.dispose, [scopeExpanded]);
    useListenable(scopeExpanded);
    final scopeLeading = <Widget>[
      if (entries.isEmpty && !operation.running && result != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(result['complete'] == true ? '没有匹配的文件' : '已检查范围内没有匹配结果'),
        ),
      if (result != null)
        Semantics(
          expanded: scopeExpanded.value,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const ListIconBadge(
              icon: LucideIcons.info,
              backgroundColor: DesignTokens.colorListIconBlue,
            ),
            trailing: Icon(
              scopeExpanded.value
                  ? LucideIcons.chevronUp
                  : LucideIcons.chevronDown,
              size: DesignTokens.componentIconActionSize,
            ),
            title: const Text('搜索范围与跳过项'),
            onTap: () => scopeExpanded.value = !scopeExpanded.value,
          ),
        ),
      if (result != null &&
          scopeExpanded.value &&
          value(result, 'limitation').isNotEmpty)
        StateNote(value(result, 'limitation')),
    ];
    final visibleIssues = result != null && scopeExpanded.value
        ? issues.length
        : 0;
    final scopeTrailing = <Widget>[
      if (result != null && scopeExpanded.value)
        const StateNote('文件可能随后变化；打开时会重新核验。子文件夹的符号链接不会跟随。'),
    ];
    final dirty =
        result != null &&
        (result['query'] != query.text.trim() ||
            result['filter'] != filter.value);
    final tooLong = utf8.encode(query.text.trim()).length > 256;
    final canSearch =
        !tooLong && (query.text.trim().isNotEmpty || filter.value != 'all');
    Future<void> search() async {
      FocusScope.of(context).unfocus();
      await operation.start(query.text.trim(), filter.value);
    }

    return PageFrame(
      title: '搜索文件',
      child: CustomScrollView(
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
                  Text(
                    '范围：$root',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (initialPath != '/sdcard')
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spacingSm,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.roundedMd,
                          ),
                        ),
                        child: Row(
                          children: [
                            for (final entire in [false, true])
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: entireStorage.value == entire,
                                  onTap: () => entireStorage.value = entire,
                                  child: Material(
                                    color: entireStorage.value == entire
                                        ? Theme.of(context).colorScheme.surface
                                        : Colors.transparent,
                                    shape: const StadiumBorder(),
                                    child: InkWell(
                                      customBorder: const StadiumBorder(),
                                      excludeFromSemantics: true,
                                      onTap: () => entireStorage.value = entire,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: DesignTokens
                                              .componentIconButtonSize,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: DesignTokens.spacingSm,
                                            vertical: DesignTokens.spacingXs,
                                          ),
                                          child: Center(
                                            child: Text(
                                              entire ? '整个共享存储' : '当前目录及子目录',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: DesignTokens.spacingSm),
                  TextField(
                    controller: query,
                    maxLength: 256,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (canSearch) search();
                    },
                    decoration: InputDecoration(
                      hintText: '输入文件名',
                      errorText: tooLong ? '搜索内容太长，请缩短文件名。' : null,
                      counterText: '',
                      prefixIcon: const Icon(
                        LucideIcons.search,
                        size: DesignTokens.componentIconActionSize,
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  ConnectSelectionField<String>(
                    label: '文件类型',
                    value: filter.value,
                    icon: Icon(
                      LucideIcons.chevronDown,
                      size: DesignTokens.componentIconSmallSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    items: [
                      for (final entry in _filters.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (next) {
                      if (next != null) filter.value = next;
                    },
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canSearch && !operation.starting
                              ? search
                              : null,
                          icon: const Icon(
                            LucideIcons.search,
                            size: DesignTokens.componentIconActionSize,
                          ),
                          label: const Text('搜索'),
                        ),
                      ),
                      if (operation.running && !operation.starting) ...[
                        const SizedBox(width: DesignTokens.spacingSm),
                        OutlinedButton(
                          onPressed: operation.stopping
                              ? null
                              : operation.cancel,
                          child: Text(operation.stopping ? '正在停止' : '停止搜索'),
                        ),
                      ],
                    ],
                  ),
                  if (operation.running)
                    const Padding(
                      padding: EdgeInsets.only(top: DesignTokens.spacingSm),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (dirty) const StateNote('条件已修改，点击搜索更新结果。'),
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: DesignTokens.spacingSm,
                      ),
                      child: Text(
                        '${switch (status) {
                          'completed' => '已完成搜索',
                          'partial' => '仅完成部分搜索',
                          'cancelled' => '已停止搜索',
                          'failed' => '搜索未完成',
                          _ => '正在搜索',
                        }} · ${entries.length} 项结果\n'
                        '已检查 ${result['visitedDirectories'] ?? 0} 个文件夹、${result['visitedEntries'] ?? 0} 项',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (operation.error != null) ...[
                    StateNote(operation.error!),
                    if (operation.searchId != null)
                      TextButton(
                        onPressed: operation.refresh,
                        child: const Text('重新核验本次搜索'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (result == null && operation.error == null && !operation.starting)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyContent(
                icon: LucideIcons.search,
                title: '在手机文件中查找',
                message: '按文件名查找，也可选择类型。仅搜索可访问目录，不读取文件正文。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingMd,
                0,
                DesignTokens.spacingMd,
                DesignTokens.spacingMd,
              ),
              sliver: SliverList.separated(
                itemCount:
                    entries.length +
                    scopeLeading.length +
                    visibleIssues +
                    scopeTrailing.length,
                separatorBuilder: (_, _) => const SizedBox.shrink(),
                itemBuilder: (context, index) {
                  if (index >= entries.length) {
                    final scopeIndex = index - entries.length;
                    if (scopeIndex < scopeLeading.length) {
                      return scopeLeading[scopeIndex];
                    }
                    final issueIndex = scopeIndex - scopeLeading.length;
                    if (issueIndex < visibleIssues) {
                      final issue = issues[issueIndex];
                      return StateNote(
                        '${value(issue, 'path')}\n${value(issue, 'reason')}',
                      );
                    }
                    return scopeTrailing[issueIndex - visibleIssues];
                  }
                  final file = entries[index];
                  final path = value(file, 'path');
                  final folder = file['isDirectory'] == true;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: ListIconBadge(
                          icon: folder ? LucideIcons.folder : LucideIcons.file,
                          backgroundColor: DesignTokens.colorListIconAmber,
                        ),
                        title: FileRowTitle(
                          name: value(file, 'name'),
                          path: value(file, 'path'),
                          size: folder ? null : bytes(file['size']),
                        ),

                        onTap: !fileCanOpen(file)
                            ? null
                            : () {
                                if (folder) {
                                  FilesRoute(
                                    deviceId: value(device, 'id'),
                                    path: path,
                                  ).push<void>(context);
                                } else {
                                  FileDetailsRoute(
                                    deviceId: value(device, 'id'),
                                    path: path,
                                  ).push<void>(context);
                                }
                              },
                      ),
                      if (!fileCanOpen(file))
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingMd,
                          ),
                          child: StateNote(
                            fileUnavailableReason(file),
                            icon: LucideIcons.circleAlert,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
