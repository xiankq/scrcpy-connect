import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';

// 日志只接收机器标识、数值和布尔值；禁止异常正文、原生日志、URI、负载及堆栈。
const _fieldNames = {
  'command',
  'code',
  'errorType',
  'scope',
  'sessionScope',
  'stage',
  'decoder',
  'decoderBackend',
  'decoderComponent',
  'backendHardwareFrames',
  'acceleration',
  'presentationPath',
  'presentedSequence',
  'platformTexturePrepared',
  'presentedToWidget',
  'codec',
  'generation',
  'captureGeneration',
  'elapsedMs',
  'width',
  'height',
  'status',
  'platform',
  'version',
  'buildMode',
  'nativeError',
  'count',
  'stoppedConfirmed',
  'textureDetached',
  'disposeRequested',
  'nativeDeleteConfirmed',
  'disposeDeferred',
  'cleanupUnconfirmed',
};

final _identifier = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{0,79}$');
final _value = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$');

Map<String, Object?> _safeFields(Map<String, Object?> fields) => {
  for (final entry in fields.entries)
    if (_fieldNames.contains(entry.key) &&
        (entry.value is bool ||
            (entry.value is num && (entry.value as num).isFinite) ||
            (entry.value is String && _value.hasMatch(entry.value as String))))
      entry.key: entry.value,
};

class DiagnosticLog {
  DiagnosticLog._(this._directory, this.maxFileBytes, this.fileCount);

  static const recentLimit = 300;
  static const pendingLimit = 256;
  final Directory _directory;
  final int maxFileBytes, fileCount;
  final _recent = ListQueue<DiagnosticRecord>();
  final _pending = <DiagnosticRecord>[];
  final _changes = StreamController<void>.broadcast();
  final _salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  Future<void> _tail = Future<void>.value();
  Future<void>? _flushing;
  Timer? _timer;
  int _lost = 0;
  bool _closed = false;
  String? storageError;
  bool historyIncomplete = false;

  Stream<void> get changes => _changes.stream;
  List<DiagnosticRecord> get recent => List.unmodifiable(_recent);

  static Future<DiagnosticLog> open(
    Directory directory, {
    int maxFileBytes = 512 * 1024,
    int fileCount = 4,
  }) async {
    if (maxFileBytes < 2048 || fileCount < 1 || fileCount > 8) {
      throw ArgumentError('Invalid diagnostic retention bounds.');
    }
    final log = DiagnosticLog._(directory, maxFileBytes, fileCount);
    try {
      await directory.create(recursive: true);
      log._recent.addAll((await log._read()).takeLast(recentLimit));
      await log._repairTail();
    } on FileSystemException catch (error) {
      log.storageError = error.runtimeType.toString();
    }
    return log;
  }

  String scope(String id) =>
      's${sha256.convert([..._salt, ...utf8.encode(id)]).toString().substring(0, 12)}';

  void record(
    DiagnosticArea area,
    String event, {
    LogLevel level = LogLevel.info,
    Map<String, Object?> fields = const {},
  }) {
    if (_closed || !_identifier.hasMatch(event)) return;
    final record = DiagnosticRecord(
      time: DateTime.now().toUtc(),
      level: level,
      area: area,
      event: event,
      fields: Map.unmodifiable(_safeFields(fields)),
    );
    _recent.add(record);
    while (_recent.length > recentLimit) {
      _recent.removeFirst();
    }
    if (_pending.length < pendingLimit) {
      _pending.add(record);
    } else {
      _lost++;
    }
    _changes.add(null);
    _schedule();
    if (level == LogLevel.error) unawaited(flush());
  }

  void _schedule() {
    if (_closed || _timer != null) return;
    _timer = Timer(const Duration(milliseconds: 250), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> flush() => _flushing ??= _serial(_writePending).whenComplete(() {
    _flushing = null;
    if (_pending.isNotEmpty) _schedule();
  });

  Future<void> _writePending() async {
    final previousError = storageError;
    final batch = [..._pending];
    _pending.clear();
    if (_lost > 0) {
      batch.add(
        DiagnosticRecord(
          time: DateTime.now().toUtc(),
          level: LogLevel.warning,
          area: DiagnosticArea.app,
          event: 'log.dropped',
          fields: {'count': _lost},
        ),
      );
      _lost = 0;
    }
    if (batch.isEmpty) return;
    try {
      await _directory.create(recursive: true);
      for (final record in batch) {
        final bytes = utf8.encode('${jsonEncode(record.toJson())}\n');
        final file = _file(0);
        final size = await _length(file);
        if (size + bytes.length > maxFileBytes) await _rotate();
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      }
      storageError = null;
    } on FileSystemException catch (error) {
      storageError = error.runtimeType.toString();
    }
    if (storageError != previousError && !_closed) _changes.add(null);
  }

  File _file(int index) => File(p.join(_directory.path, 'events.$index.jsonl'));

  Future<int> _length(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 0;
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('Invalid diagnostic file.');
    }
    return file.length();
  }

  Future<void> _rotate() async {
    final oldest = _file(fileCount - 1);
    await _length(oldest);
    if (await oldest.exists()) await oldest.delete();
    for (var index = fileCount - 2; index >= 0; index--) {
      final file = _file(index);
      if (await _length(file) > 0) await file.rename(_file(index + 1).path);
    }
  }

  Future<void> _repairTail() async {
    final file = _file(0);
    final length = await _length(file);
    if (length == 0 || length > maxFileBytes) return;
    final bytes = await file.readAsBytes();
    if (bytes.last == 10) return;
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.truncate(bytes.lastIndexOf(10) + 1);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<List<DiagnosticRecord>> _read() async {
    final records = <DiagnosticRecord>[];
    for (var index = fileCount - 1; index >= 0; index--) {
      final file = _file(index);
      final length = await _length(file);
      if (length == 0) continue;
      if (length > maxFileBytes) {
        historyIncomplete = true;
        continue;
      }
      final lines = const LineSplitter().convert(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
      );
      for (final line in lines) {
        final Object? value;
        try {
          value = jsonDecode(line);
        } on FormatException {
          historyIncomplete = true;
          continue;
        }
        if (value case {
          'time': String time,
          'level': String level,
          'area': String area,
          'event': String event,
          'fields': Map<String, Object?> fields,
        }) {
          final parsedTime = DateTime.tryParse(time);
          final parsedLevel = LogLevel.values
              .where((item) => item.name == level)
              .firstOrNull;
          final parsedArea = DiagnosticArea.values
              .where((item) => item.name == area)
              .firstOrNull;
          if (parsedTime != null &&
              parsedLevel != null &&
              parsedArea != null &&
              _identifier.hasMatch(event)) {
            records.add(
              DiagnosticRecord(
                time: parsedTime,
                level: parsedLevel,
                area: parsedArea,
                event: event,
                fields: Map.unmodifiable(_safeFields(fields)),
              ),
            );
            continue;
          }
        }
        historyIncomplete = true;
      }
    }
    return records;
  }

  Future<Uint8List> export() async {
    return _serial(() async {
      await _writePending();
      final records = storageError == null ? await _read() : recent;
      return Uint8List.fromList(
        utf8.encode(
          '${records.map((r) => jsonEncode(r.toJson())).join('\n')}\n',
        ),
      );
    });
  }

  Future<void> clear() async {
    await _serial(() async {
      for (var index = 0; index < fileCount; index++) {
        final file = _file(index);
        if (await _length(file) > 0) await file.delete();
      }
      _pending.clear();
      _recent.clear();
      historyIncomplete = false;
      _lost = 0;
      storageError = null;
      if (!_closed) _changes.add(null);
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await flush();
    // 正在执行的刷新可能只捕获了较早批次。
    if (_pending.isNotEmpty) await flush();
    await _changes.close();
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length > count ? length - count : 0);
}
