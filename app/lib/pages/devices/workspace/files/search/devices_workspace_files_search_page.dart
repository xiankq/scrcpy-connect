import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/services/files/file_browser.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/widgets/file_search_controls.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/widgets/file_search_result_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/file_search_controller.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

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
    final scopePath = entireStorage.value ? '/sdcard' : initialPath;
    final operation = useMemoized(
      () => FileSearchController(controller.execute, value(device, 'id')),
      [controller, device['id']],
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
            result['filter'] != filter.value ||
            result['path'] != scopePath);
    final tooLong = utf8.encode(query.text.trim()).length > 256;
    final canSearch =
        !tooLong && (query.text.trim().isNotEmpty || filter.value != 'all');
    final running = operation.running;
    Future<void> search() async {
      FocusScope.of(context).unfocus();
      await operation.start(query.text.trim(), filter.value, path: scopePath);
    }

    return PageFrame(
      title: '文件搜索',
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
                    _currentDirectoryLine(scopePath),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  FileSearchScopeSelector(
                    entireStorage: entireStorage.value,
                    onChanged: (entire) => entireStorage.value = entire,
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final field = TextField(
                        controller: query,
                        maxLength: 256,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          if (canSearch && !running) search();
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
                      );
                      final type = FileSearchTypeField(
                        value: filter.value,
                        onChanged: (next) => filter.value = next,
                      );
                      if (constraints.maxWidth /
                              MediaQuery.textScalerOf(context).scale(1) <
                          360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            field,
                            const SizedBox(height: DesignTokens.spacingSm),
                            type,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 2, child: field),
                          const SizedBox(width: DesignTokens.spacingSm),
                          Expanded(child: type),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  SizedBox(
                    width: double.infinity,

                    child: running
                        ? FilledButton(
                            onPressed: operation.stopping
                                ? null
                                : operation.cancel,
                            child: Text(
                              operation.stopping
                                  ? '正在停止…'
                                  : operation.starting
                                  ? '正在开始搜索…'
                                  : '停止搜索',
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: canSearch ? search : null,
                            icon: const Icon(
                              LucideIcons.search,
                              size: DesignTokens.componentIconActionSize,
                            ),
                            label: const Text('搜索'),
                          ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: DesignTokens.spacingMd),
                    Text(
                      _searchStatusTitle(status, entries.length),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: DesignTokens.spacingXxs),
                    Text(
                      _checkedRangeLine(
                        result,
                        status,
                        issues,
                        scopeLabel: _submittedScopeLabel(result),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (dirty) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      _dirtyLine(result),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
                message: '按文件名查找，也可选择类型。搜索只读取名称，结果会随可访问范围检查逐步出现。',
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
              sliver: SliverList.builder(
                itemCount:
                    entries.length +
                    (result == null ? 0 : issues.length) +
                    (result != null && entries.isEmpty && !running ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < entries.length) {
                    final file = entries[index];
                    final path = value(file, 'path');
                    final folder = file['isDirectory'] == true;
                    return FileSearchResultRow(
                      key: ValueKey(('search-result', path)),
                      file: file,
                      folder: folder,
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
                      unavailableReason: fileCanOpen(file)
                          ? null
                          : fileUnavailableReason(file),
                    );
                  }
                  var remainder = index - entries.length;
                  if (remainder < issues.length) {
                    final issue = issues[remainder];
                    return StateNote(
                      '${value(issue, 'path')}\n${value(issue, 'reason')}',
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spacingLg,
                    ),
                    child: Text(
                      result?['complete'] == true ? '没有匹配的文件' : '已检查范围内没有匹配结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

String _submittedScopeLabel(Json result) =>
    value(result, 'path') == '/sdcard' ? '手机内部存储' : '当前目录及子目录';

String _searchStatusTitle(String status, int count) => switch (status) {
  'completed' => '找到 $count 项',
  'partial' => '仅完成部分搜索 · 找到 $count 项',
  'cancelled' => '已停止 · 保留 $count 项',
  'failed' => '搜索未完成 · 找到 $count 项',
  _ => '搜索中 · 已找到 $count 项',
};

String _checkedRangeLine(
  Json result,
  String status,
  List<Json> issues, {
  required String scopeLabel,
}) {
  final directories = result['visitedDirectories'] ?? 0;
  final entries = result['visitedEntries'] ?? 0;
  final skipped = issues
      .where((issue) => value(issue, 'code') == 'permission_denied')
      .length;
  final base =
      '$scopeLabel · 已检查 ${_countLabel(directories)} 个文件夹 / '
      '${_countLabel(entries)} 项';
  final current = value(result, 'currentDirectory');
  if (status == 'running' && current.isNotEmpty) {
    final checked = _currentDirectoryLabel(current);
    return checked.isEmpty ? base : '$base\n正在检查 $checked';
  }
  if (issues.isEmpty) {
    return status == 'running' ? '$base\n结果会随检查范围逐步增加。' : base;
  }
  if (skipped > 0 && (status == 'cancelled' || status == 'partial')) {
    return '$base\n跳过 $skipped 个无权限目录；其余目录未搜索。';
  }
  if (skipped > 0) {
    return '$base\n跳过 $skipped 个无权限目录；结果不完整。';
  }
  if (status == 'cancelled' || status == 'partial') {
    return '$base\n其余目录未搜索。';
  }
  return '$base\n${issues.length} 个目录或项目未能完成；结果不完整。';
}

String _countLabel(Object? value) {
  final text = value?.toString() ?? '0';
  final number = int.tryParse(text);
  if (number == null) return text;
  final digits = number.toString();
  final output = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) output.write(',');
    output.write(digits[index]);
  }
  return output.toString();
}

String _dirtyLine(Json? result) {
  final previous = value(result ?? {}, 'query').trim();
  return previous.isEmpty
      ? '条件已修改。以下是上次条件的结果，点击搜索更新。'
      : '条件已修改。以下仍为“$previous”的结果，点击搜索更新。';
}

String _currentDirectoryLine(String path) {
  if (path == '/sdcard') return '当前目录：手机存储 /';
  final crumbs = fileBreadcrumbs(path);
  final labels = path.startsWith('/sdcard/')
      ? crumbs.skip(1).map((crumb) => crumb.label)
      : crumbs.map((crumb) => crumb.label);
  return '当前目录：${labels.join(' / ')} /';
}

String _currentDirectoryLabel(String path) {
  if (path == '/sdcard') return '手机内部存储';
  final crumbs = fileBreadcrumbs(path);
  if (path.startsWith('/sdcard/')) {
    return crumbs.skip(1).map((crumb) => crumb.label).join(' / ');
  }
  return crumbs.map((crumb) => crumb.label).join(' / ');
}
