import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/application/app_controller.dart';

/// 一个核心租约可由页面和异步本机消费者共享，所有消费者关闭后文件才能回收。
class MediaCacheLease {
  MediaCacheLease(this.controller, this.id);
  final AppController controller;
  final String id;
  int _references = 1;
  bool _ownerReleased = false;

  static MediaCacheLease? fromReceipt(AppController controller, Json data) {
    final id = value(data, 'cacheLeaseId', value(data, 'leaseId'));
    return id.isEmpty ? null : MediaCacheLease(controller, id);
  }

  VoidCallback hold() {
    if (_references == 0) throw StateError('The cache lease has ended.');
    _references++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _releaseReference();
    };
  }

  void release() {
    if (_ownerReleased) return;
    _ownerReleased = true;
    _releaseReference();
  }

  void _releaseReference() {
    if (--_references != 0) return;
    unawaited(
      controller
          .execute(ApplicationCommand.mediaCacheRelease, {'leaseId': id})
          .then<void>(
            (_) {},
            // 释放失败时保守保留核心保护，不删除文件或改为释放其他令牌。
            onError: (Object _, StackTrace _) {},
          ),
    );
  }
}

/// 即使页面已离开，仍拥有请求并负责回收迟到回执携带的租约。
class MediaCacheRequest {
  MediaCacheRequest(this.controller, this.command, this.params);
  final AppController controller;
  final String command;
  final Json params;
  bool _disposed = false;
  MediaCacheLease? lease;
  late final Future<Json> result = _load();

  Future<Json> _load() async {
    final data = await controller.request(command, params);
    lease = MediaCacheLease.fromReceipt(controller, data);
    if (_disposed) {
      lease?.release();
      throw const RequestFailure('cancelled', '已离开本次内容。');
    }
    return data;
  }

  void dispose() {
    _disposed = true;
    lease?.release();
  }
}

/// 任务页或导出表单使用已准备原件时持有其缓存保护。
AsyncSnapshot<Json> useTransferCacheLease(
  AppController controller,
  String? transferId,
) {
  final request = useMemoized(
    () => transferId == null || transferId.isEmpty
        ? null
        : MediaCacheRequest(controller, 'media.cache.acquire', {
            'transferId': transferId,
          }),
    [controller, transferId],
  );
  useEffect(() => request?.dispose, [request]);
  return useFuture(request?.result, preserveState: false);
}
