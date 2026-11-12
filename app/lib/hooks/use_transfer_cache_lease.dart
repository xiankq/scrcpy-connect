import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';

/// 任务页或导出表单使用已准备原件时持有其缓存保护。
AsyncSnapshot<String> useTransferCacheLease(WidgetRef ref, String? transferId) {
  final acquireLease = ref.watch(transferCacheLeaseProvider);
  final content = ref.watch(contentReaderProvider);
  final request = useMemoized(
    () => transferId == null || transferId.isEmpty
        ? null
        : ContentCacheRequest(() => acquireLease(transferId), (id) async {
            await content.releaseLease(id);
          }, leaseId: (id) => id),
    [acquireLease, content, transferId],
  );
  useEffect(() => request?.dispose, [request]);
  return useFuture(request?.result, preserveState: false);
}
