import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';

/// 任务页或导出表单使用已准备原件时持有其缓存保护。
AsyncSnapshot<String> useTransferCacheLease(
  AppNotifier controller,
  String? transferId,
) {
  final request = useMemoized(
    () => transferId == null || transferId.isEmpty
        ? null
        : ContentCacheRequest(
            () => controller.acquireTransferCacheLease(transferId),
            (id) async {
              await controller.content.releaseLease(id);
            },
            leaseId: (id) => id,
          ),
    [controller, transferId],
  );
  useEffect(() => request?.dispose, [request]);
  return useFuture(request?.result, preserveState: false);
}
