import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/media/media_cache_lease.dart';

/// 任务页或导出表单使用已准备原件时持有其缓存保护。
AsyncSnapshot<Json> useTransferCacheLease(
  AppController controller,
  String? transferId,
) {
  final request = useMemoized(
    () => transferId == null || transferId.isEmpty
        ? null
        : MediaCacheRequest(
            controller.request,
            controller.execute,
            'media.cache.acquire',
            {'transferId': transferId},
          ),
    [controller, transferId],
  );
  useEffect(() => request?.dispose, [request]);
  return useFuture(request?.result, preserveState: false);
}
