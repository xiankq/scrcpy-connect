import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/services/files/file_type_policy.dart';
import 'package:scrcpy_connect/services/files/file_paths.dart';

/// 拥有目录浏览、搜索与图库快照；不持有持久传输状态。
final class FileCatalog {
  FileCatalog(this.executor);
  final FileExecutor executor;
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  Stream<Map<String, Object?>> get events => _events.stream;
  final Map<String, _Scan> _scans = {};
  bool _closed = false;
  void _check() {
    if (_closed) throw const FileFailure('closed', '文件浏览已关闭。');
  }

  static String mime(String path) => FileTypePolicy.mime(path);
  static String _id() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = bytes[6] & 15 | 64;
    bytes[8] = bytes[8] & 63 | 128;
    final text = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }

  static bool _matches(Map<String, Object?> entry, String filter) =>
      switch (filter) {
        'all' => true,
        'folders' => entry['kind'] == 'directory',
        'images' || 'videos' || 'audio' || 'documents' || 'archives' =>
          FileTypePolicy.kind(
                name: entry['name'] as String? ?? '',
                mime: entry['mime'] as String?,
              ).name ==
              filter,
        _ => throw const FileFailure('invalid_argument', '文件类型无效。'),
      };

  static Map<String, Object?> _entry(String root, FileEntryFact fact) {
    final name = fact.pathName;
    return {
      'name': fact.displayName,
      'path': name == null ? null : p.posix.join(root, name),
      'kind': fact.stamp?.kind ?? 'failed',
      'isDirectory': fact.stamp?.isDirectory ?? false,
      'isSymlink': fact.stamp?.isLink ?? false,
      'nameIsUtf8': name != null,
      'canOpen': name != null && fact.error == null,
      'canManage': name != null && fact.error == null,
      'size': fact.stamp?.size ?? 0,
      'modified': fact.stamp?.modifiedSeconds ?? 0,
      'modifiedSeconds': fact.stamp?.modifiedSeconds ?? 0,
      'mime': mime(fact.displayName),
      'mode': fact.stamp?.mode ?? 0,
      'selectable':
          name != null &&
          fact.error == null &&
          (fact.stamp?.isFile == true || fact.stamp?.isDirectory == true),
      if (name == null) 'errorCode': 'invalid_filename',
      if (fact.error != null) 'errorCode': fact.error!.code,
    };
  }

  Future<Map<String, Object?>> browse(
    String device,
    String path, {
    String filter = 'all',
    String sort = 'name',
    bool descending = false,
    int offset = 0,
    int limit = 200,
    FileCancellation? cancellation,
  }) async {
    _check();
    path = FilePaths.remote(path);
    if (offset < 0 ||
        limit < 1 ||
        limit > 10000 ||
        !const ['name', 'size', 'modified', 'type'].contains(sort)) {
      throw const FileFailure('invalid_argument', '分页或排序参数无效。');
    }
    final token = cancellation ?? FileCancellation();
    final facts = await executor.list(
      device,
      path,
      local: false,
      limit: 10000,
      cancellation: token,
    );
    token.check();
    final entries = facts.entries
        .map((e) => _entry(path, e))
        .where((e) => _matches(e, filter))
        .toList();
    entries.sort((a, b) {
      final directory = (a['kind'] == 'directory' ? 0 : 1).compareTo(
        b['kind'] == 'directory' ? 0 : 1,
      );
      if (directory != 0) return directory;
      final int result = switch (sort) {
        'size' => (a['size']! as int).compareTo(b['size']! as int),
        'modified' => (a['modified']! as int).compareTo(b['modified']! as int),
        'type' => (a['mime']! as String).compareTo(b['mime']! as String),
        _ => (a['name']! as String).toLowerCase().compareTo(
          (b['name']! as String).toLowerCase(),
        ),
      };
      return (descending ? -result : result) != 0
          ? (descending ? -result : result)
          : (a['name']! as String).compareTo(b['name']! as String);
    });
    return {
      'path': path,
      'entries': entries.skip(offset).take(limit).toList(),
      'total': entries.length,
      'offset': offset,
      'hasMore': offset + limit < entries.length,
      'truncated': facts.truncated,
    };
  }

  Map<String, Object?> startSearch(
    String device,
    String root, {
    required String query,
    String filter = 'all',
    bool gallery = false,
  }) {
    _check();
    root = FilePaths.remote(root);
    if (utf8.encode(query).length > 256 ||
        query.contains('\u0000') ||
        (!gallery && query.trim().isEmpty && filter == 'all')) {
      throw const FileFailure('invalid_argument', '请输入最多256字节的文件名或选择文件类型。');
    }
    _matches({'mime': '', 'kind': ''}, filter);
    if (_scans.values.where((s) => s.status == 'running').length >= 4) {
      throw const FileFailure('busy', '搜索或扫描数量已达到上限。');
    }
    while (_scans.length >= 16) {
      final old = _scans.entries
          .where((e) => e.value.status != 'running')
          .firstOrNull;
      if (old == null) break;
      _scans.remove(old.key);
    }
    final scan = _Scan(
      _id(),
      device,
      root,
      query.toLowerCase(),
      filter,
      gallery,
    );
    _scans[scan.id] = scan;
    scan.worker = _walk(scan);
    return scan.snapshot();
  }

  Future<void> _walk(_Scan scan) async {
    final timer = Timer(const Duration(seconds: 30), () {
      scan.timedOut = true;
      scan.cancellation.cancel();
    });
    final queue = Queue<(String, int)>()..add((scan.root, 0));
    var directories = 0, bytes = 0;
    try {
      final root = await executor.stat(
        scan.device,
        scan.root,
        local: false,
        followStorageAlias: true,
        cancellation: scan.cancellation,
      );
      if (!root.isDirectory) {
        throw const FileFailure('not_directory', '搜索根路径不是目录。');
      }
      while (queue.isNotEmpty) {
        scan.cancellation.check();
        final (path, depth) = queue.removeFirst();
        scan.currentDirectory = path;
        scan.visitedDirectories = directories + 1;
        if (++directories > (scan.gallery ? 4096 : 2048)) {
          scan.limited = true;
          break;
        }
        DirectoryFacts facts;
        try {
          facts = await executor.list(
            scan.device,
            path,
            local: false,
            limit: 4096,
            cancellation: scan.cancellation,
          );
        } on FileFailure catch (e) {
          if (e.code == 'cancelled') rethrow;
          scan.issue(path, e.code, e.message);
          continue;
        }
        if (facts.truncated) {
          scan.issue(path, 'directory_limit', '目录超过4096项。');
          scan.limited = true;
        }
        for (final fact in facts.entries) {
          scan.cancellation.check();
          if (++scan.visited > 50000) {
            scan.limited = true;
            break;
          }
          final entry = _entry(path, fact);
          final child = entry['path'] as String?;
          if (child == null || fact.error != null) {
            scan.issue(
              path,
              fact.error?.code ?? 'invalid_filename',
              fact.error?.message ?? '文件名不能表示为有效文字。',
            );
            continue;
          }
          if (scan.gallery &&
              (child == '/sdcard/Android/data' ||
                  child == '/sdcard/Android/obb')) {
            continue;
          }
          if (fact.stamp?.isDirectory == true) {
            if (depth < 32) {
              queue.add((child, depth + 1));
            } else {
              scan.limited = true;
              scan.issue(child, 'depth_limit', '已达到32层目录深度。');
            }
          }
          if (scan.gallery
              ? fact.stamp?.isFile == true &&
                    ((entry['mime']! as String).startsWith('image/') ||
                        (entry['mime']! as String).startsWith('video/'))
              : (entry['name']! as String).toLowerCase().contains(scan.query) &&
                    _matches(entry, scan.filter)) {
            bytes += utf8.encode(child).length + 256;
            if (scan.entries.length >= (scan.gallery ? 25000 : 500) ||
                bytes > 8 * 1024 * 1024) {
              scan.limited = true;
              break;
            }
            scan.entries.add(entry);
          }
        }
        if (scan.visited > 50000 ||
            scan.entries.length >= (scan.gallery ? 25000 : 500) ||
            bytes > 8 * 1024 * 1024) {
          break;
        }
      }
      scan.status = scan.limited || scan.issues.isNotEmpty
          ? 'partial'
          : 'completed';
    } on FileFailure catch (e) {
      if (e.code == 'cancelled') {
        scan.status = scan.timedOut ? 'partial' : 'cancelled';
      } else {
        scan.issue(scan.root, e.code, e.message);
        scan.status = 'failed';
      }
    } catch (e) {
      scan.issue(scan.root, 'scan_failed', '$e');
      scan.status = 'failed';
    } finally {
      timer.cancel();
      if (scan.gallery) {
        scan.entries.sort((a, b) {
          final modified = (b['modified']! as int).compareTo(
            a['modified']! as int,
          );
          return modified != 0
              ? modified
              : (a['path']! as String).compareTo(b['path']! as String);
        });
      }
      if (!_closed) {
        _events.add({
          'type': scan.gallery ? 'media.scan.changed' : 'files.search.changed',
          'deviceId': scan.device,
          'scanId': scan.id,
          'searchId': scan.id,
        });
      }
    }
  }

  Map<String, Object?> scan(
    String device,
    String id, {
    int offset = 0,
    int limit = 100,
  }) {
    final scan = _scans[id];
    if (scan == null) throw const FileFailure('search_not_found', '搜索记录已过期。');
    if (scan.device != device) {
      throw const FileFailure('search_device_mismatch', '搜索属于另一台设备。');
    }
    if (offset < 0 || limit < 1 || limit > 500) {
      throw const FileFailure('invalid_argument', '分页参数无效。');
    }
    return scan.snapshot(offset: offset, limit: limit);
  }

  Future<Map<String, Object?>> cancelScan(String device, String id) async {
    final scan = _scans[id];
    if (scan == null || scan.device != device) {
      throw const FileFailure('search_not_found', '搜索不存在。');
    }
    scan.cancellation.cancel();
    await scan.worker;
    return scan.snapshot();
  }

  Future<void> cancelDevice(String device) async {
    final scans = _scans.values.where((s) => s.device == device).toList();
    for (final scan in scans) {
      scan.cancellation.cancel();
    }
    await Future.wait(scans.map((s) => s.worker));
  }

  Future<void> close() async {
    _closed = true;
    for (final scan in _scans.values) {
      scan.cancellation.cancel();
    }
    await Future.wait(_scans.values.map((s) => s.worker));
    await _events.close();
  }
}

class _Scan {
  _Scan(this.id, this.device, this.root, this.query, this.filter, this.gallery);
  final String id, device, root, query, filter;
  final bool gallery;
  final cancellation = FileCancellation();
  final entries = <Map<String, Object?>>[], issues = <Map<String, Object?>>[];
  String status = 'running';
  int visited = 0, visitedDirectories = 0;
  String currentDirectory = '';
  bool limited = false, timedOut = false;
  Future<void> worker = Future.value();
  void issue(String path, String code, String reason) {
    if (issues.length < 128) {
      issues.add({'path': path, 'code': code, 'reason': reason});
    }
  }

  Map<String, Object?> snapshot({int offset = 0, int limit = 500}) {
    final ready = !gallery || status != 'running';
    final page = ready
        ? entries.skip(offset).take(limit).toList()
        : <Map<String, Object?>>[];
    final total = ready ? entries.length : 0;
    return {
      'deviceId': device,
      'searchId': id,
      'scanId': id,
      'path': root,
      'query': query,
      'filter': filter,
      'status': gallery && status == 'running'
          ? 'scanning'
          : gallery && status == 'failed'
          ? 'partial'
          : status,
      'complete': status == 'completed',
      'canCancel': status == 'running',
      'visitedEntries': visited,
      'visitedDirectories': visitedDirectories,
      'currentDirectory': currentDirectory,
      'issues': List<Map<String, Object?>>.of(issues),
      'issueCount': issues.length,
      'results': page,
      'items': page,
      'entries': page,
      'total': total,
      'hasMore': ready && offset + page.length < total,
      'nextOffset': ready && offset + page.length < total
          ? offset + page.length
          : null,
      'offset': offset,
      'limited': limited || timedOut,
      'truncated': limited || timedOut,
      'snapshot': ready,
      'scope': {
        'roots': [root],
        'recognition': 'fileExtension',
        'modifiedSource': 'mtimeUnixSeconds',
        'followsChildSymlinks': false,
        'consistency': 'bestEffortDirectoryMetadata',
        'refresh': 'newIndependentSnapshot',
      },
      'limitation':
          '按名称或扩展名检查；最多30秒、50000项、32层，每目录4096项，不跟随子符号链接；目录变化可能使结果不完整。',
    };
  }
}
