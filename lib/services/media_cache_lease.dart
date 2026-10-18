import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// One Core lease can have a page owner and asynchronous local consumers.
/// The file becomes reclaimable only after every consumer has finished closing.
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
          .execute(InteropCommand.mediaCacheRelease, {'leaseId': id})
          .then<void>(
            (_) {},
            // A failed release conservatively retains the Core protection. Never
            // fall back to removing files or releasing a different token.
            onError: (Object _, StackTrace _) {},
          ),
    );
  }
}

/// Owns a request even if its reply arrives after the requesting page leaves.
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

/// Pins a prepared original while its public task page or export form uses it.
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
