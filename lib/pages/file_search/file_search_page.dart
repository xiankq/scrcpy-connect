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
      subtitle: deviceName(device),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Glass(
                        radius: 26,
                        child: Row(
                          children: [
                            for (final entire in [false, true])
                              Expanded(
                                child: ChoiceChip(
                                  showCheckmark: false,
                                  label: Text(
                                    entire ? '整个共享存储' : '当前目录及子目录',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: entireStorage.value == entire,
                                  shape: const StadiumBorder(),
                                  selectedColor: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  labelStyle: TextStyle(
                                    color: entireStorage.value == entire
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                  ),
                                  onSelected: (_) =>
                                      entireStorage.value = entire,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
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
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in _filters.entries)
                        ChoiceChip(
                          showCheckmark: false,
                          label: Text(entry.value),
                          shape: const StadiumBorder(),
                          selectedColor: Theme.of(context).colorScheme.primary,
                          labelStyle: TextStyle(
                            color: filter.value == entry.key
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          selected: filter.value == entry.key,
                          onSelected: (_) => filter.value = entry.key,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canSearch && !operation.starting
                              ? search
                              : null,
                          icon: const Icon(LucideIcons.search, size: 18),
                          label: const Text('搜索'),
                        ),
                      ),
                      if (operation.running && !operation.starting) ...[
                        const SizedBox(width: 12),
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
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (dirty) const StateNote('条件已修改，点击搜索更新结果。'),
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
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
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverList.separated(
                itemCount: entries.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == entries.length) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entries.isEmpty &&
                            !operation.running &&
                            result != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              result['complete'] == true
                                  ? '没有匹配的文件'
                                  : '已检查范围内没有匹配结果',
                            ),
                          ),
                        if (result != null)
                          ExpansionTile(
                            key: ValueKey('$status:${issues.length}'),
                            tilePadding: EdgeInsets.zero,
                            leading: const Icon(
                              LucideIcons.info,
                              color: ConnectTokens.amber,
                            ),
                            trailing: const Icon(
                              LucideIcons.chevronDown,
                              size: 18,
                            ),
                            title: const Text('搜索范围与跳过项'),
                            subtitle: Text(
                              issues.isEmpty
                                  ? '按文件名搜索，打开时重新核验'
                                  : '${issues.length} 处范围或内容需要核对',
                            ),
                            initiallyExpanded: issues.isNotEmpty,
                            children: [
                              if (value(result, 'limitation').isNotEmpty)
                                StateNote(value(result, 'limitation')),
                              for (final issue in issues)
                                StateNote(
                                  '${value(issue, 'path')}\n${value(issue, 'reason')}',
                                ),
                              const StateNote(
                                '文件可能随后变化；打开时会重新核验。子文件夹的符号链接不会跟随。',
                              ),
                            ],
                          ),
                      ],
                    );
                  }
                  final file = entries[index];
                  final path = value(file, 'path');
                  final folder = file['isDirectory'] == true;
                  final parent = path.lastIndexOf('/') > 0
                      ? path.substring(0, path.lastIndexOf('/'))
                      : '/';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    leading: FeatureIcon(
                      folder ? LucideIcons.folder : LucideIcons.file,
                      color: ConnectTokens.amber,
                      size: 44,
                    ),
                    title: Text(value(file, 'name')),
                    subtitle: Text(
                      fileCanOpen(file)
                          ? '$parent\n${folder ? '文件夹' : bytes(file['size'])}'
                          : fileUnavailableReason(file),
                    ),
                    isThreeLine: true,
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
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
