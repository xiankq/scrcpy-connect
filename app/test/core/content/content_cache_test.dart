import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';

void main() {
  test('可在旧 outgoing 路径已消失后恢复到当前应用容器', () async {
    final systemTemp = Directory(
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    final base = await systemTemp.createTemp('content-cache-');
    addTearDown(() => base.delete(recursive: true));
    final root = Directory('${base.path}/data')..createSync(recursive: true);
    final previous = '${base.path}/old-container/Library/Caches/outgoing';
    final current = '${base.path}/current-container/Library/Caches/outgoing';
    await Directory('${base.path}/old-container/Library/Application Support')
        .create(recursive: true);
    await File('${root.path}/media-cache.json').writeAsString(
      jsonEncode({
        'budgetBytes': defaultMediaCacheBudget,
        'outgoingDirectory': previous,
        'retainedShares': <String>[],
      }),
    );

    final cache = await ContentCache.open(root: root);
    await cache.configure(outgoingDirectory: current);

    final stored = jsonDecode(
      await File('${root.path}/media-cache.json').readAsString(),
    ) as Map<String, Object?>;
    expect(stored['outgoingDirectory'], current);
  });

  test('仍保护存在的旧 outgoing 路径，不能静默替换', () async {
    final systemTemp = Directory(
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    final base = await systemTemp.createTemp('content-cache-');
    addTearDown(() => base.delete(recursive: true));
    final root = Directory('${base.path}/data')..createSync(recursive: true);
    final previous = '${base.path}/old/outgoing';
    final current = '${base.path}/current/outgoing';
    await Directory(previous).create(recursive: true);
    await File('${root.path}/media-cache.json').writeAsString(
      jsonEncode({
        'budgetBytes': defaultMediaCacheBudget,
        'outgoingDirectory': previous,
        'retainedShares': <String>[],
      }),
    );

    final cache = await ContentCache.open(root: root);
    await expectLater(
      cache.configure(outgoingDirectory: current),
      throwsA(
        isA<ContentCacheFailure>().having(
          (failure) => failure.code,
          'code',
          'cache_configuration_conflict',
        ),
      ),
    );
  });
}
