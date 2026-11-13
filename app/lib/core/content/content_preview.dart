import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/models/cached_content.dart';
import 'package:scrcpy_connect/core/content/thumbnail_jobs.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/files/file_cache_leases.dart';
import 'package:scrcpy_connect/core/files/models/file_cache_reservation.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/models/file_kind.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:uuid/uuid.dart';

export 'package:scrcpy_connect/core/content/models/cached_content.dart';

/// 页面与队列只借用内容读取和读保护，不取得任务所有者的关闭权。
abstract interface class ContentReader {
  Future<CachedContent> preview({
    required String deviceId,
    required String path,
  });
  Future<CachedContent> thumbnail({
    required String deviceId,
    required String path,
    required String operationId,
    int maxSize = 256,
  });
  Future<void> cancelThumbnail({
    required String deviceId,
    required String operationId,
  });
  Future<void> releaseLease(String leaseId);
}

/// 应用拥有媒体版本、校验、写入预算及读租约；执行器仅传输文件或执行伴生 RPC。
final class ContentPreview implements ContentReader {
  ContentPreview({
    required this.cache,
    required this.executor,
    required this.jobs,
    this.isDisposed,
  });
  final ContentCache cache;
  final FileExecutor executor;
  final ThumbnailJobs jobs;
  final bool Function()? isDisposed;
  final _active = <String, _Operation>{};
  final _seen = <String, bool>{};
  final _queues = <String, Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;
  final _stoppingDevices = <String>{};
  final _deviceClosings = <String, Future<void>>{};
  static const _maxThumbnail = ThumbnailImage.maxBytes;

  @override
  Future<CachedContent> preview({
    required String deviceId,
    required String path,
  }) => _load(device: deviceId, path: path);

  @override
  Future<CachedContent> thumbnail({
    required String deviceId,
    required String path,
    required String operationId,
    int maxSize = 256,
  }) => _load(
    device: deviceId,
    path: path,
    operationId: operationId,
    thumbnailSize: maxSize,
  );

  @override
  Future<void> cancelThumbnail({
    required String deviceId,
    required String operationId,
  }) async {
    _cancelThumbnail(deviceId, operationId);
  }

  @override
  Future<void> releaseLease(String leaseId) => cache.release(leaseId);

  void _checkDevice(String device) {
    if (device.isEmpty || device.contains('\u0000')) {
      throw const RequestFailure('invalid_argument', '设备标识无效。');
    }
    if (_closed ||
        isDisposed?.call() == true ||
        _stoppingDevices.contains(device)) {
      throw const RequestFailure('disposed', '媒体缓存所有者已关闭。');
    }
  }

  void _cancelThumbnail(String device, String operationId) {
    _checkDevice(device);
    final operation = _uuid(operationId);
    final key = '$device:$operation';
    final active = _active[key];
    final fresh = !_seen.containsKey(key);
    if (fresh) _claim(key, true);
    active?.cancel();
  }

  Future<CachedContent> _load({
    required String device,
    required String path,
    String? operationId,
    int? thumbnailSize,
  }) async {
    _checkDevice(device);
    path = FilePaths.remote(path);
    final thumbnail = operationId != null;
    if (thumbnail &&
        (thumbnailSize == null || thumbnailSize < 64 || thumbnailSize > 512)) {
      throw const RequestFailure('invalid_argument', '缩略图尺寸必须在 64–512 之间。');
    }
    final operation = thumbnail ? _uuid(operationId) : _uuid(null);
    final key = '$device:$operation';
    if (_active.values.where((task) => task.device == device).length >= 16) {
      throw const RequestFailure('busy', '这台设备正在处理的媒体请求已达到上限。');
    }
    _claim(key, false);
    final task = _Operation(device);
    _active[key] = task;
    final timer = Timer(Duration(seconds: thumbnail ? 45 : 300), () {
      task.timeout = true;
      task.cancel();
    });
    final queueKey = thumbnail ? 'thumbnail:$device' : 'preview:$device:$path';
    final previous = _queues[queueKey] ?? Future<void>.value();
    final completed = Completer<void>();
    _queues[queueKey] = completed.future;
    task.onReleased = () {
      // 被取消的排队者不能让后来的请求越过仍在运行的前任。
      unawaited(
        previous.then((_) {
          if (!completed.isCompleted) completed.complete();
        }),
      );
      unawaited(
        completed.future.then((_) {
          if (identical(_queues[queueKey], completed.future)) {
            _queues.remove(queueKey);
          }
        }),
      );
      if (identical(_active[key], task)) _active.remove(key);
    };
    var returning = false;
    try {
      await Future.any([previous, task.token.whenCancelled]);
      task.check();
      final result = thumbnail
          ? await _thumbnail(device, path, thumbnailSize!, operation, task)
          : await _preview(device, path, task);
      task.check();
      returning = true;
      return result;
    } on Object catch (error) {
      if (task.timeout &&
          (error is FileFailure && error.code == 'cancelled' ||
              error is RequestFailure && error.code == 'cancelled')) {
        task.check();
      }
      if (error is FileSystemException) {
        throw RequestFailure('io_error', error.message);
      }
      rethrow;
    } finally {
      timer.cancel();
      try {
        await task.releaseResources();
        if (returning && !task.token.isCancelled) {
          // 只有执行与写入保护均确认释放后，才把读租约交给实际调用者。
          task.resultLease = null;
        } else {
          await task.releaseResult(cache);
        }
        task.onReleased();
        if (returning) task.check();
      } finally {
        task.done.complete();
      }
    }
  }

  void _claim(String key, bool cancelled) {
    if (_seen.containsKey(key)) {
      throw RequestFailure(
        _seen[key]! ? 'cancelled' : 'operation_reused',
        '此媒体操作已结束或取消，请使用新的操作标识。',
      );
    }
    if (_seen.length >= 65536) {
      throw const RequestFailure('operation_limit', '媒体操作标识已达到本次附着上限。');
    }
    _seen[key] = cancelled;
  }

  Future<void> cancelDevice(String device) {
    _stoppingDevices.add(device);
    return _deviceClosings[device] ??=
        _stopTasks(
              _active.values.where((task) => task.device == device).toList(),
            )
            .then((_) {
              _stoppingDevices.remove(device);
            })
            .whenComplete(() {
              _deviceClosings.remove(device);
            });
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _stopTasks(_active.values.toList()).whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _stopTasks(List<_Operation> tasks) async {
    for (final task in tasks) {
      task.cancel();
    }
    Object? failure;
    StackTrace? failureStack;
    for (final task in tasks) {
      try {
        // 先唤醒实际 SDK worker；若失败则立即保留任务，不永远等待阻塞读取。
        await task.reader?.close();
        await task.done.future;
        await task.releaseResources();
        await task.releaseResult(cache);
        task.onReleased();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<T> _runJob<T>(
    ThumbnailJob job,
    _Operation task,
    Future<T> Function(ThumbnailJob) execute,
  ) async {
    task.check();
    final id = job.operationId;
    Future<void>? cancelling;
    final remove = task.token.onCancel(() {
      cancelling = jobs.cancel(task.device, id);
      unawaited(cancelling!.catchError((Object _) {}));
    });
    try {
      final result = await execute(job);
      task.check();
      return result;
    } finally {
      remove();
      if (cancelling != null) {
        try {
          await cancelling;
        } catch (_) {
          /* 原执行 Future 的回收结果决定是否能发布。 */
        }
      }
    }
  }

  Future<CachedContent> _preview(
    String device,
    String path,
    _Operation task,
  ) async {
    final files = executor;
    if (files is! FileReadExecutor) {
      throw const RequestFailure('unsupported', '文件执行器不支持精确预览生命周期。');
    }
    final reader = await (files as FileReadExecutor).beginRead(
      device,
      cancellation: task.token,
    );
    task.reader = reader;
    task.check();
    final source = await reader.stat(path);
    if (!source.isFile) {
      throw const RequestFailure('not_a_file', '预览源必须是普通文件。');
    }
    final key = _hash(utf8.encode('$device\u0000$path'));
    final version = _hash(utf8.encode(jsonEncode(source.toJson())));
    final directory = Directory(
      p.join(cache.root.path, 'media', '$key-$version'),
    );
    final lookup = await cache.writer(
      directory.path,
      0,
      name: p.posix.basename(path),
      sourceLabel: device,
      sourcePath: path,
    );
    task.writer = lookup;
    try {
      final metadata = await _metadata(directory);
      if (metadata != null && _same(metadata['source'], source.toJson())) {
        final target = _artifact(directory, metadata['artifact']);
        if (target != null &&
            await _validFile(
              target,
              metadata['localSize'],
              metadata['sha256'],
            )) {
          final lease = await cache.reserve([
            FileCacheReservation(
              directory.path,
              0,
              name: p.posix.basename(path),
              sourceLabel: device,
              sourcePath: path,
            ),
          ]);
          task.resultLease = lease;
          return CachedContent(
            path: target.path,
            leaseId: lease,
            cacheHit: true,
          );
        }
      }
    } finally {
      await lookup.close();
      task.writer = null;
    }
    task.writer = await cache.writer(
      directory.path,
      source.size + 4096,
      name: p.posix.basename(path),
      sourceLabel: device,
      sourcePath: path,
    );
    final extension = p.posix.extension(path).replaceFirst('.', '');
    final suffix = RegExp(r'^[a-zA-Z0-9]{1,12}$').hasMatch(extension)
        ? extension
        : 'bin';
    final target = File(p.join(directory.path, '${_uuid(null)}.$suffix'));
    final temporary = File(p.join(directory.path, '.${_uuid(null)}.part'));
    await directory.create(recursive: true);
    final count = await reader.copy(
      path,
      temporary.path,
      expected: source,
      onProgress: (_) {},
    );
    task.check();
    final after = await reader.stat(path);
    if (count != source.size || after != source) {
      throw const RequestFailure('source_changed', '预览源文件发生变化，请重新打开。');
    }
    if (await temporary.length() != count) {
      throw const RequestFailure('source_changed', '预览传输字节数不一致。');
    }
    final digest = (await sha256.bind(temporary.openRead()).first).toString();
    await reader.commit(temporary.path, target.path);
    await _publish(directory, {
      'version': 1,
      'source': source.toJson(),
      'localSize': count,
      'sha256': digest,
      'artifact': p.basename(target.path),
    });
    task.check();
    final lease = await cache.reserve([
      FileCacheReservation(
        directory.path,
        0,
        name: p.posix.basename(path),
        sourceLabel: device,
        sourcePath: path,
      ),
    ]);
    task.resultLease = lease;
    return CachedContent(path: target.path, leaseId: lease);
  }

  Future<CachedContent> _thumbnail(
    String device,
    String path,
    int maxSize,
    String operation,
    _Operation task,
  ) async {
    final mime = FileKind.mimeForPath(path);
    final kind = mime.startsWith('image/')
        ? ThumbnailKind.image
        : mime.startsWith('video/')
        ? ThumbnailKind.video
        : null;
    if (kind == null) {
      throw const RequestFailure(
        'media_type_unknown',
        '此路径的媒体类型尚未识别，不能自动下载原内容作为缩略图。',
      );
    }
    ThumbnailJob request() => ThumbnailJob(
      deviceId: device,
      path: path,
      kind: kind,
      maxSize: maxSize,
      ownerOperationId: operation,
      operationId: _uuid(null),
    );
    final source = await _runJob(request(), task, jobs.readSource);
    final key = _hash(
      utf8.encode('thumbnail-v1\u0000$device\u0000$path\u0000$maxSize'),
    );
    final version = _hash(utf8.encode(jsonEncode(source.toJson())));
    final directory = Directory(
      p.join(cache.root.path, 'media', 'thumbnails', '$key-$version'),
    );
    final lookup = await cache.writer(
      directory.path,
      0,
      name: p.posix.basename(path),
      sourceLabel: device,
      sourcePath: path,
    );
    task.writer = lookup;
    try {
      final metadata = await _metadata(directory);
      if (metadata != null &&
          metadata['version'] == 1 &&
          _same(metadata['source'], source.toJson())) {
        final target = _artifact(directory, metadata['artifact']);
        if (target != null &&
            await _validFile(
              target,
              metadata['jpegBytes'],
              metadata['sha256'],
              maximum: _maxThumbnail,
            )) {
          final dimensions = await _cachedDimensions(target);
          if (dimensions != null &&
              dimensions.width == metadata['width'] &&
              dimensions.height == metadata['height'] &&
              dimensions.width <= maxSize &&
              dimensions.height <= maxSize) {
            final lease = await cache.reserve([
              FileCacheReservation(
                directory.path,
                0,
                name: p.posix.basename(path),
                sourceLabel: device,
                sourcePath: path,
              ),
            ]);
            task.resultLease = lease;
            return CachedContent(
              path: target.path,
              leaseId: lease,
              cacheHit: true,
            );
          }
        }
      }
    } finally {
      await lookup.close();
      task.writer = null;
    }
    task.writer = await cache.writer(
      directory.path,
      _maxThumbnail + 4096,
      name: p.posix.basename(path),
      sourceLabel: device,
      sourcePath: path,
    );
    final image = await _runJob(request(), task, jobs.render);
    if (image.source != source) {
      throw const RequestFailure('source_changed', '生成期间媒体源或缩略图类型发生变化。');
    }
    final after = await _runJob(request(), task, jobs.readSource);
    if (after != source) {
      throw const RequestFailure('source_changed', '媒体源已经变化，请重新获取缩略图。');
    }
    task.check();
    await directory.create(recursive: true);
    final target = File(
      p.join(directory.path, '${_uuid(null)}-${image.digest}.jpg'),
    );
    await target.writeAsBytes(image.jpeg, flush: true);
    await _publish(directory, {
      'version': 1,
      'source': source.toJson(),
      'sha256': image.digest,
      'jpegBytes': image.jpeg.length,
      'width': image.width,
      'height': image.height,
      'artifact': p.basename(target.path),
    });
    task.check();
    final lease = await cache.reserve([
      FileCacheReservation(
        directory.path,
        0,
        name: p.posix.basename(path),
        sourceLabel: device,
        sourcePath: path,
      ),
    ]);
    task.resultLease = lease;
    return CachedContent(path: target.path, leaseId: lease);
  }

  static Future<Map<String, dynamic>?> _metadata(Directory directory) async {
    try {
      final file = File(p.join(directory.path, 'metadata.json'));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 4096) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? value : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static File? _artifact(Directory directory, Object? name) =>
      name is String &&
          name.isNotEmpty &&
          !name.contains('/') &&
          !name.contains('\\') &&
          !name.contains('..')
      ? File(p.join(directory.path, name))
      : null;
  static Future<bool> _validFile(
    File file,
    Object? size,
    Object? digest, {
    int? maximum,
  }) async {
    if (size is! int ||
        size < 0 ||
        maximum != null && size > maximum ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      return false;
    }
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != size) {
        return false;
      }
      return (await sha256.bind(file.openRead()).first).toString() == digest;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> _publish(
    Directory directory,
    Map<String, dynamic> metadata,
  ) async {
    final bytes = utf8.encode(jsonEncode(metadata));
    if (bytes.length > 4096) {
      throw const RequestFailure('invalid_metadata', '媒体缓存元数据超过上限。');
    }
    final file = File(p.join(directory.path, '.${_uuid(null)}.metadata'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(p.join(directory.path, 'metadata.json'));
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  static Future<({int width, int height})?> _cachedDimensions(
    File target,
  ) async {
    try {
      return ThumbnailImage.readDimensions(await target.readAsBytes());
    } on RequestFailure {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  static String _uuid(Object? value) {
    if (value != null) {
      if (value is! String ||
          !RegExp(
            r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
          ).hasMatch(value)) {
        throw const RequestFailure('invalid_argument', '媒体操作标识必须是 UUID。');
      }
      return value.toLowerCase();
    }
    return const Uuid().v4();
  }
}

final class _Operation {
  _Operation(this.device);
  final String device;
  final token = FileCancellation();
  final done = Completer<void>();
  bool timeout = false;
  FileReadBatch? reader;
  CacheWriter? writer;
  String? resultLease;
  late final void Function() onReleased;
  Future<void>? _releasing;

  Future<void> releaseResources() =>
      _releasing ??= _releaseResources().whenComplete(() {
        _releasing = null;
      });
  Future<void> _releaseResources() async {
    try {
      await reader?.close();
      reader = null;
      await writer?.close();
      writer = null;
    } catch (error) {
      throw RequestFailure(
        'media_cleanup_unconfirmed',
        '媒体执行或缓存保护尚未确认释放：$error',
      );
    }
  }

  Future<void> releaseResult(ContentCache cache) async {
    if (resultLease case final lease?) {
      await cache.release(lease);
      resultLease = null;
    }
  }

  void cancel() => token.cancel();
  void check() {
    if (timeout) {
      throw const RequestFailure('media_timeout', '媒体请求超过有界等待时间。');
    }
    token.check();
  }
}
