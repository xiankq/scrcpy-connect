import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/content/thumbnail_queue_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

import '../../support/fixed_state.dart';

void main() {
  test('缩略图换源取消原操作，迟到租约只由原内容能力释放', () async {
    final previous = _Content();
    final replacement = _Content();
    final container = ProviderContainer(
      overrides: [contentReaderProvider.overrideWithValue(previous)],
    );
    addTearDown(container.dispose);
    final provider = thumbnailQueueProvider('device');
    container.listen(provider, (_, _) {});
    final queue = container.read(provider);
    final lease = queue.acquire('/photo');
    final cancelled = expectLater(
      lease.result,
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    await flushProviders(container);
    expect(previous.loads, hasLength(1));
    container.updateOverrides([
      contentReaderProvider.overrideWithValue(replacement),
    ]);
    await flushProviders(container);
    await cancelled;
    expect(previous.cancelled, [previous.loads.single.operationId]);
    final currentLease = container.read(provider).acquire('/new');
    await flushProviders(container);
    previous.loads.single.result.complete(
      const CachedContent(path: '/old-local', leaseId: 'old-lease'),
    );
    replacement.loads.single.result.complete(
      const CachedContent(path: '/new-local', leaseId: 'new-lease'),
    );
    expect((await currentLease.result).path, '/new-local');
    await flushProviders(container);
    expect(previous.released, ['old-lease']);
    expect(replacement.released, isEmpty);
    currentLease.release();
    currentLease.release();
    await flushProviders(container);
    expect(replacement.released, ['new-lease']);
    expect(replacement.cancelled, isEmpty);
  });

  test('页面释放正在读取的缩略图，后续请求仍等待原通道终态', () async {
    final content = _Content();
    final container = ProviderContainer(
      overrides: [contentReaderProvider.overrideWithValue(content)],
    );
    addTearDown(container.dispose);
    final provider = thumbnailQueueProvider('device');
    final listener = container.listen(provider, (_, _) {});
    final queue = container.read(provider);
    final first = queue.acquire('/first');
    final cancelled = expectLater(first.result, throwsA(isA<RequestFailure>()));
    await flushProviders(container);
    first.release();
    listener.close();
    await flushProviders(container);
    final reopened = container.listen(provider, (_, _) {});
    expect(container.read(provider), same(queue));
    final second = queue.acquire('/second');
    await flushProviders(container);
    expect(content.loads, hasLength(1));
    content.loads[0].result.complete(
      const CachedContent(path: '/retired', leaseId: 'retired'),
    );
    await cancelled;
    await flushProviders(container);
    expect(content.loads, hasLength(2));
    expect(content.released, ['retired']);
    content.loads[1].result.complete(
      const CachedContent(path: '/latest', leaseId: 'latest'),
    );
    await second.result;
    second.release();
    reopened.close();
    await flushProviders(container);
    expect(content.released, ['retired', 'latest']);
    expect(content.cancelled, [content.loads[0].operationId]);
  });
}

class _Content implements ContentReader {
  final loads = <({String operationId, Completer<CachedContent> result})>[];
  final cancelled = <String>[];
  final released = <String>[];
  @override
  Future<CachedContent> thumbnail({
    required String deviceId,
    required String path,
    required String operationId,
    int maxSize = 256,
  }) {
    final result = Completer<CachedContent>();
    loads.add((operationId: operationId, result: result));
    return result.future;
  }

  @override
  Future<void> cancelThumbnail({
    required String deviceId,
    required String operationId,
  }) async => cancelled.add(operationId);
  @override
  Future<void> releaseLease(String leaseId) async => released.add(leaseId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
