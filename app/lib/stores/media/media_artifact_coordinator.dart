import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/files/file_paths.dart';
import 'package:scrcpy_connect/services/files/file_type_policy.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/media/app_media_cache.dart';

typedef MediaArtifactRequest = Future<Map<String, dynamic>> Function(
  String command,
  Map<String, dynamic> params,
);

/// 应用拥有媒体版本、校验、写入预算及读租约；执行器仅传输文件或执行伴生 RPC。
final class MediaArtifactCoordinator {
  MediaArtifactCoordinator({
    required this.cache,
    required this.executor,
    required this.request,
    this.emit,
  });
  final AppMediaCache cache;
  final FileExecutor executor;
  final MediaArtifactRequest request;
  final void Function(Map<String, dynamic>)? emit;
  final _active = <String, _Operation>{};
  final _seen = <String, bool>{};
  final _queues = <String, Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;
  final _stoppingDevices = <String>{};
  final _deviceClosings = <String, Future<void>>{};
  static const _maxThumbnail = 256 * 1024;

  Future<Map<String, dynamic>> invoke(
    String command,
    Map<String, dynamic> params,
  ) async {
    final device = _text(params, 'deviceId');
    if (_closed || _stoppingDevices.contains(device)) {
      throw const RequestFailure('disposed', '媒体缓存所有者已关闭。');
    }
    if (command == 'media.thumbnail.cancel') {
      final operation = _uuid(params['operationId']);
      final key = '$device:$operation';
      final active = _active[key];
      final fresh = !_seen.containsKey(key);
      if (fresh) _claim(key, true);
      active?.cancel();
      return {
        'operationId': operation,
        'cancelRequested': active != null || fresh,
        'alreadyFinished': active == null && !fresh,
        'status': active != null
            ? 'cancelling'
            : fresh
            ? 'cancelledBeforeStart'
            : 'finished',
      };
    }
    final thumbnail = command == 'media.thumbnail';
    final path = FilePaths.remote(_text(params, 'path'));
    final operation = thumbnail ? _uuid(params['operationId']) : _uuid(null);
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
      if (thumbnail) {
        emit?.call({
          'type': 'media.thumbnail.started',
          'deviceId': device,
          'data': {'operationId': operation},
        });
      }
      final result = thumbnail
          ? await _thumbnail(
              device,
              path,
              params['maxSize'] ?? 256,
              operation,
              task,
            )
          : await _preview(device, path, task);
      task.check();
      returning = true;
      return {...result, if (thumbnail) 'operationId': operation};
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

  Future<Map<String, dynamic>> _rpc(
    String phase,
    Map<String, dynamic> params,
    _Operation task,
  ) async {
    task.check();
    final id = _uuid(null);
    Future<void>? cancelling;
    final remove = task.token.onCancel(() {
      cancelling = request('media.thumbnail.cancel', {
        'deviceId': task.device,
        'operationId': id,
      }).then<void>((_) {});
      unawaited(cancelling!.catchError((Object _) {}));
    });
    try {
      final result = await request('media.thumbnail', {
        ...params,
        'deviceId': task.device,
        'operationId': id,
        'execution': phase,
      });
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

  Future<Map<String, dynamic>> _preview(
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
          return {
            'localPath': target.path,
            'cacheLeaseId': lease,
            'mime': FileTypePolicy.mime(path),
            'cacheHit': true,
            'size': source.size,
            'sourceValidation': 'sizeModeMtimeSeconds',
            'thumbnail': false,
          };
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
    return {
      'localPath': target.path,
      'cacheLeaseId': lease,
      'mime': FileTypePolicy.mime(path),
      'cacheHit': false,
      'size': source.size,
      'sourceValidation': 'sizeModeMtimeSeconds',
      'thumbnail': false,
    };
  }

  Future<Map<String, dynamic>> _thumbnail(
    String device,
    String path,
    Object? maxSize,
    String operation,
    _Operation task,
  ) async {
    if (maxSize is! int || maxSize < 64 || maxSize > 512) {
      throw const RequestFailure('invalid_argument', '缩略图尺寸必须在 64–512 之间。');
    }
    final mime = FileTypePolicy.mime(path);
    final kind = mime.startsWith('image/')
        ? 'image'
        : mime.startsWith('video/')
        ? 'video'
        : null;
    if (kind == null) {
      throw const RequestFailure(
        'media_type_unknown',
        '此路径的媒体类型尚未识别，不能自动下载原内容作为缩略图。',
      );
    }
    final params = <String, dynamic>{
      'path': path,
      'kind': kind,
      'maxSize': maxSize,
      'ownerOperationId': operation,
    };
    final before = await _rpc('stat', params, task);
    final source = _source(before['sourceStamp']);
    var transferred = _count(before['rpcBytesReceived']);
    final key = _hash(
      utf8.encode('thumbnail-v1\u0000$device\u0000$path\u0000$maxSize'),
    );
    final version = _hash(utf8.encode(jsonEncode(source)));
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
          _same(metadata['source'], source)) {
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
              dimensions.$1 == metadata['width'] &&
              dimensions.$2 == metadata['height'] &&
              dimensions.$1 <= maxSize &&
              dimensions.$2 <= maxSize) {
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
            return _thumbnailReceipt(
              target,
              lease,
              source,
              dimensions,
              metadata['jpegBytes'] as int,
              transferred,
              true,
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
    final response = await _rpc('thumbnail', params, task);
    transferred += _count(response['rpcBytesReceived']);
    if (!_same(_source(response['sourceStamp']), source) ||
        response['thumbnail'] != true ||
        response['mime'] != 'image/jpeg') {
      throw const RequestFailure('source_changed', '生成期间媒体源或缩略图类型发生变化。');
    }
    final encoded = response['data'];
    if (encoded is! String || encoded.length > ((_maxThumbnail + 2) ~/ 3) * 4) {
      throw const RequestFailure('invalid_thumbnail', '缩略图数据缺失或超过大小限制。');
    }
    final Uint8List jpeg;
    try {
      jpeg = base64Decode(encoded);
    } on FormatException {
      throw const RequestFailure('invalid_thumbnail', '缩略图编码无效。');
    }
    final digest = _hash(jpeg), dimensions = _jpeg(jpeg);
    if (jpeg.length > _maxThumbnail ||
        response['sha256'] != digest ||
        response['jpegBytes'] != jpeg.length ||
        response['width'] != dimensions.$1 ||
        response['height'] != dimensions.$2 ||
        dimensions.$1 > maxSize ||
        dimensions.$2 > maxSize) {
      throw const RequestFailure('invalid_thumbnail', '缩略图摘要、大小或尺寸不一致。');
    }
    final after = await _rpc('stat', params, task);
    transferred += _count(after['rpcBytesReceived']);
    if (!_same(_source(after['sourceStamp']), source)) {
      throw const RequestFailure('source_changed', '媒体源已经变化，请重新获取缩略图。');
    }
    task.check();
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '${_uuid(null)}-$digest.jpg'));
    await target.writeAsBytes(jpeg, flush: true);
    await _publish(directory, {
      'version': 1,
      'source': source,
      'sha256': digest,
      'jpegBytes': jpeg.length,
      'width': dimensions.$1,
      'height': dimensions.$2,
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
    return {
      ..._thumbnailReceipt(
        target,
        lease,
        source,
        dimensions,
        jpeg.length,
        transferred,
        false,
      ),
      for (final key in ['orientationApplied', 'orientation', 'videoRotation'])
        key: response[key],
    };
  }

  static Map<String, dynamic> _thumbnailReceipt(
    File target,
    String lease,
    Map<String, dynamic> source,
    (int, int) dimensions,
    int bytes,
    int transferred,
    bool hit,
  ) => {
    'localPath': target.path,
    'cacheLeaseId': lease,
    'mime': 'image/jpeg',
    'thumbnail': true,
    'width': dimensions.$1,
    'height': dimensions.$2,
    'originalSize': source['size'],
    'cacheHit': hit,
    'sourceStamp': source,
    'sourceValidation':
        source['modifiedNanos'] != null && source['changedNanos'] != null
        ? 'descriptorDeviceInodeSizeModeMtimeCtimeWithNanosecondFields'
        : 'descriptorDeviceInodeSizeModeMtimeCtimeSeconds',
    'bytesTransferred': transferred,
    'jpegBytes': bytes,
    'jpegBytesTransferred': hit ? 0 : bytes,
    'originalBytesTransferred': 0,
    'transferAccounting': 'companionJsonPayloadBytes',
  };

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

  static Map<String, dynamic> _source(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const RequestFailure('invalid_data', '缩略图源元数据无效。');
    }
    final mode = value['mode'], size = value['size'];
    if (mode is! int ||
        mode & 0xf000 != 0x8000 ||
        size is! int ||
        size < 0 ||
        size > 64 * 1024 * 1024 * 1024 ||
        value['device'] is! String ||
        int.tryParse(value['device'] as String) == null ||
        value['inode'] is! String ||
        int.tryParse(value['inode'] as String) == null ||
        value['modifiedSeconds'] is! int ||
        value['changedSeconds'] is! int) {
      throw const RequestFailure('invalid_data', '缩略图源元数据无效。');
    }
    for (final key in ['modifiedNanos', 'changedNanos']) {
      final nanos = value[key];
      if (nanos != null &&
          (nanos is! int || nanos < 0 || nanos >= 1000000000)) {
        throw const RequestFailure('invalid_data', '缩略图源时间精度无效。');
      }
    }
    return {
      for (final key in [
        'device',
        'inode',
        'mode',
        'size',
        'modifiedSeconds',
        'changedSeconds',
        'modifiedNanos',
        'changedNanos',
      ])
        key: value[key],
    };
  }

  static Future<(int, int)?> _cachedDimensions(File target) async {
    try {
      return _jpeg(await target.readAsBytes());
    } on RequestFailure {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static (int, int) _jpeg(List<int> bytes) {
    const invalid = RequestFailure('invalid_thumbnail', '缩略图 JPEG 结构或尺寸无效。');
    if (bytes.length < 4 ||
        bytes[0] != 255 ||
        bytes[1] != 216 ||
        bytes[bytes.length - 2] != 255 ||
        bytes.last != 217) {
      throw invalid;
    }
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 255) throw invalid;
      while (offset < bytes.length && bytes[offset] == 255) {
        offset++;
      }
      if (offset >= bytes.length) throw invalid;
      final marker = bytes[offset++];
      if (marker == 218 || marker == 217) throw invalid;
      if (marker == 1 || marker >= 208 && marker <= 216) continue;
      if (offset + 2 > bytes.length) throw invalid;
      final length = bytes[offset] * 256 + bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) throw invalid;
      if (marker >= 192 && marker <= 194) {
        if (length < 8 || bytes[offset + 2] != 8) throw invalid;
        final height = bytes[offset + 3] * 256 + bytes[offset + 4],
            width = bytes[offset + 5] * 256 + bytes[offset + 6];
        if (width == 0 || height == 0) throw invalid;
        return (width, height);
      }
      offset += length;
    }
    throw invalid;
  }

  static int _count(Object? value) => value is int && value >= 0 ? value : 0;
  static bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  static String _text(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty || value.contains('\u0000')) {
      throw RequestFailure('invalid_argument', '缺少有效字段：$key');
    }
    return value;
  }

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

  Future<void> releaseResult(AppMediaCache cache) async {
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
