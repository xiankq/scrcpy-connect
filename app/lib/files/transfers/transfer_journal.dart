import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/files/execution/file_executor.dart';

/// 文件传输任务的持久日志；迁移、追加与压缩保持同一条提交序列。
class TransferJournal {
  TransferJournal(this.root);
  final Directory root;
  File get file => File(p.join(root.path, 'file_tasks.v2.journal'));
  bool poisoned = false;
  int sequence = 0;
  int _records = 0, _bytes = 0;
  final _rows = <String, Map<String, Object?>>{};
  Future<void> _pending = Future.value();
  Future<Map<String, Map<String, Object?>>> load() async {
    final tasks = <String, Map<String, Object?>>{};
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _bytes = bytes.length;
      if (bytes.isNotEmpty && bytes.last != 10) {
        throw const FileFailure('transfer_storage_corrupt', '任务日志尾部不完整，原文件保留。');
      }
      for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
        final value = jsonDecode(line) as Map<String, dynamic>;
        _records++;
        if (value['version'] != 2 || value['sequence'] != ++sequence) {
          throw const FileFailure('transfer_storage_corrupt', '任务日志序号或版本无效。');
        }
        final task = value['task'];
        if (task != null) {
          final row = Map<String, Object?>.from(task as Map);
          final id = row['id'];
          if (id is! String ||
              id.isEmpty ||
              (row['generation'] as int? ?? 0) <
                  (tasks[id]?['generation'] as int? ?? 0)) {
            throw const FileFailure('transfer_storage_corrupt', '任务身份或尝试代际无效。');
          }
          tasks[row['id']! as String] = row;
        }
        if (value['remove'] != null) tasks.remove(value['remove']);
        for (final id in value['removed'] as List? ?? const []) {
          tasks.remove(id);
        }
      }
      _rows.addAll(
        tasks.map((id, task) => MapEntry(id, Map<String, Object?>.from(task))),
      );
      return tasks;
    }
    // 只读旧 Rust 检查点和日志，不修改或删除它们。
    final checkpoint = File(p.join(root.path, 'transfers.json')),
        legacyJournal = File(p.join(root.path, 'transfers.journal'));
    var legacySequence = 0;
    var checkpointPresent = false;
    if (await checkpoint.exists()) {
      final value = jsonDecode(await checkpoint.readAsString());
      final List<dynamic> records;
      if (value is List) {
        records = value;
      } else {
        final map = value as Map<String, dynamic>;
        if (map['version'] != 1) {
          throw const FileFailure('transfer_storage_corrupt', '旧任务存储版本不受支持。');
        }
        legacySequence = map['sequence'] as int;
        checkpointPresent = true;
        records = map['transfers'] as List;
      }
      for (final record in records) {
        final row = Map<String, Object?>.from(record as Map);
        final id = row['id'];
        if (id is! String || id.isEmpty || tasks.containsKey(id)) {
          throw const FileFailure('transfer_storage_corrupt', '旧任务身份无效或重复。');
        }
        tasks[id] = row;
      }
    }
    if (await legacyJournal.exists()) {
      final bytes = await legacyJournal.readAsBytes();
      if (bytes.isNotEmpty && (!checkpointPresent || bytes.last != 10)) {
        throw const FileFailure(
          'transfer_storage_corrupt',
          '旧任务日志缺少检查点或尾部不完整。',
        );
      }
      int? previous;
      for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
        final delta = jsonDecode(line) as Map<String, dynamic>;
        final seq = delta['sequence'] as int;
        if (delta['version'] != 1 ||
            seq < 1 ||
            previous != null && seq != previous + 1) {
          throw const FileFailure('transfer_storage_corrupt', '旧任务日志不连续。');
        }
        previous = seq;
        if (seq <= legacySequence) continue;
        if (seq != legacySequence + 1) {
          throw const FileFailure('transfer_storage_corrupt', '旧任务日志缺少记录。');
        }
        for (final entry
            in (delta['upserts'] as Map<String, dynamic>).entries) {
          final row = Map<String, Object?>.from(entry.value as Map);
          if (row['id'] != entry.key) {
            throw const FileFailure('transfer_storage_corrupt', '旧任务日志身份不一致。');
          }
          final incoming = row['generation'] as int? ?? 0,
              saved = tasks[entry.key]?['generation'] as int? ?? 0;
          if (incoming < 0 || incoming < saved) {
            throw const FileFailure(
              'transfer_storage_corrupt',
              '旧代际覆盖较新的任务记录。',
            );
          }
          tasks[entry.key] = row;
        }
        for (final id in delta['removed'] as List) {
          tasks.remove(id);
        }
        legacySequence = seq;
      }
    }
    await root.create(recursive: true);
    // 在未发布文件内完成迁移；崩溃时保留旧存储。
    final temporary = File('${file.path}.migration');
    if (await temporary.exists()) await temporary.delete();
    await temporary.create(exclusive: true);
    final handle = await temporary.open(mode: FileMode.writeOnly);
    try {
      for (final task in tasks.values) {
        await handle.writeString(
          '${jsonEncode({'version': 2, 'sequence': ++sequence, 'task': task})}\n',
        );
      }
      if (tasks.isEmpty) {
        await handle.writeString(
          '${jsonEncode({'version': 2, 'sequence': ++sequence, 'migrationComplete': true})}\n',
        );
      }
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temporary.rename(file.path);
    _rows.addAll(
      tasks.map((id, task) => MapEntry(id, Map<String, Object?>.from(task))),
    );
    _records = sequence;
    _bytes = await file.length();
    return tasks;
  }

  Future<void> upsert(Map<String, Object?> task) => _enqueue({'task': task});
  Future<void> removeMany(List<String> ids) => _enqueue({'removed': ids});
  Future<void> _enqueue(Map<String, Object?> change) {
    final write = _pending.then((_) => _append(change));
    _pending = write;
    return write;
  }

  Future<void> _append(Map<String, Object?> change) async {
    if (poisoned) {
      throw const FileFailure(
        'transfer_storage_corrupt',
        '日志写入曾失败，禁止继续执行文件任务。',
      );
    }
    try {
      final bytes = utf8.encode(
        '${jsonEncode({'version': 2, 'sequence': sequence + 1, ...change})}\n',
      );
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      sequence++;
      _records++;
      _bytes += bytes.length;
      final task = change['task'];
      if (task is Map<String, Object?>) {
        _rows[task['id']! as String] = Map.of(task);
      }
      if (change['remove'] is String) _rows.remove(change['remove']);
      for (final id in change['removed'] as List? ?? const []) {
        _rows.remove(id);
      }
      if (_rows.isEmpty ||
          _records > _rows.length + 1024 ||
          _bytes > 4 * 1024 * 1024 && _records > _rows.length + 128) {
        await _compact();
      }
    } catch (_) {
      poisoned = true;
      rethrow;
    }
  }

  Future<void> _compact() async {
    final temporary = File('${file.path}.compact');
    if (await temporary.exists()) await temporary.delete();
    await temporary.create(exclusive: true);
    final handle = await temporary.open(mode: FileMode.writeOnly);
    var next = 0;
    try {
      for (final task in _rows.values) {
        await handle.writeString(
          '${jsonEncode({'version': 2, 'sequence': ++next, 'task': task})}\n',
        );
      }
      if (_rows.isEmpty) {
        await handle.writeString(
          '${jsonEncode({'version': 2, 'sequence': ++next, 'migrationComplete': true})}\n',
        );
      }
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temporary.rename(file.path);
    sequence = next;
    _records = next;
    _bytes = await file.length();
  }
}
