import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/models/file_kind.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_facts.dart';
import 'package:scrcpy_connect/core/files/models/file_entry_fact.dart';
import 'package:scrcpy_connect/core/files/models/file_search_changed.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_scan_changed.dart';
import 'package:uuid/uuid.dart';

/// 拥有目录浏览、搜索与图库快照；不持有持久传输状态。
final class FileCatalog implements FileSearch, GalleryScanner, FileDirectories {
  FileCatalog(this.executor);
  final FileExecutor executor;
  final _events = StreamController<AppEvent>.broadcast(sync: true);
  Stream<AppEvent> get events => _events.stream;
  final Map<String, _Scan> _scans = {};
  bool _closed = false;
  void _check() {
    if (_closed) throw const FileFailure('closed', '文件浏览已关闭。');
  }

  static String mime(String path) => FileKind.mimeForPath(path);

  static bool _matches(FileCatalogEntry entry, FileCatalogFilter filter) =>
      switch (filter) {
        .all => true,
        .folders => entry.kind == 'directory',
        .images || .videos || .audio || .documents || .archives =>
          FileKind.classify(name: entry.name, mime: entry.mime).name ==
              filter.name,
      };

  static FileCatalogEntry _entry(String root, FileEntryFact fact) {
    final name = fact.pathName;
    return FileCatalogEntry(
      name: fact.displayName,
      path: name == null ? null : p.posix.join(root, name),
      kind: fact.stamp?.kind ?? 'failed',
      isDirectory: fact.stamp?.isDirectory ?? false,
      isSymlink: fact.stamp?.isLink ?? false,
      nameIsUtf8: name != null,
      canOpen: name != null && fact.error == null,
      canManage: name != null && fact.error == null,
      size: fact.stamp?.size,
      modified: fact.stamp?.modifiedSeconds,
      modifiedSeconds: fact.stamp?.modifiedSeconds ?? 0,
      mime: mime(fact.displayName),
      mode: fact.stamp?.mode ?? 0,
      sourceIdentity: fact.stamp?.identity,
      sourceStamp: fact.stamp,
      selectable:
          name != null &&
          fact.error == null &&
          (fact.stamp?.isFile == true || fact.stamp?.isDirectory == true),
      errorCode: fact.error?.code ?? (name == null ? 'invalid_filename' : null),
    );
  }

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) async {
    _check();
    final path = FilePaths.remote(target.path);
    if (offset < 0 || limit < 1 || limit > 10000) {
      throw const FileFailure('invalid_argument', '分页或排序参数无效。');
    }
    final token = cancellation ?? FileCancellation();
    token.check();
    final facts = await executor.list(
      target.deviceId,
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
      final directory = (a.kind == 'directory' ? 0 : 1).compareTo(
        b.kind == 'directory' ? 0 : 1,
      );
      if (directory != 0) return directory;
      final int result = switch (sort) {
        .size => (a.size ?? 0).compareTo(b.size ?? 0),
        .modified => (a.modified ?? 0).compareTo(b.modified ?? 0),
        .type => a.mime.compareTo(b.mime),
        .name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return (descending ? -result : result) != 0
          ? (descending ? -result : result)
          : a.name.compareTo(b.name);
    });
    return FileDirectorySnapshot(
      deviceId: target.deviceId,
      path: path,
      entries: List.unmodifiable(entries.skip(offset).take(limit)),
      total: entries.length,
      offset: offset,
      hasMore: offset + limit < entries.length,
      truncated: facts.truncated,
    );
  }

  @override
  Future<GalleryScanSnapshot> startScan(
    String deviceId, {
    int limit = 100,
  }) async {
    _check();
    _checkPage(0, limit);
    return _startScan(
      deviceId,
      '/sdcard',
      query: '',
      gallery: true,
    ).gallerySnapshot(limit: limit);
  }

  @override
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  }) async {
    _check();
    final scan = _gallery(target);
    _checkPage(offset, limit);
    return scan.gallerySnapshot(offset: offset, limit: limit);
  }

  @override
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target) async {
    _check();
    final scan = _gallery(target, forCancellation: true);
    scan.cancellation.cancel();
    await scan.worker;
    return scan.gallerySnapshot();
  }

  _Scan _gallery(GalleryScanTarget target, {bool forCancellation = false}) {
    if (target.scanId.isEmpty || target.scanId.contains('\u0000')) {
      throw const FileFailure('invalid_argument', '相册检查标识无效。');
    }
    if (forCancellation && _scans[target.scanId]?.device != target.deviceId) {
      throw const FileFailure('search_not_found', '搜索不存在。');
    }
    final scan = _findScan(target.deviceId, target.scanId);
    if (!scan.gallery) {
      throw const FileFailure('scan_type_mismatch', '此任务不属于相册检查。');
    }
    return scan;
  }

  _Scan _startScan(
    String device,
    String root, {
    required String query,
    FileCatalogFilter filter = .all,
    bool gallery = false,
  }) {
    _check();
    root = FilePaths.remote(root);
    if (utf8.encode(query).length > 256 ||
        query.contains('\u0000') ||
        (!gallery && query.trim().isEmpty && filter == .all)) {
      throw const FileFailure('invalid_argument', '请输入最多256字节的文件名或选择文件类型。');
    }
    _matches(const FileCatalogEntry(mime: '', kind: ''), filter);
    if (_scans.values.where((s) => s.status == .running).length >= 4) {
      throw const FileFailure('busy', '搜索或扫描数量已达到上限。');
    }
    while (_scans.length >= 16) {
      final old = _scans.entries
          .where((e) => e.value.status != .running)
          .firstOrNull;
      if (old == null) break;
      _scans.remove(old.key);
    }
    final scan = _Scan(const Uuid().v4(), device, root, query, filter, gallery);
    _scans[scan.id] = scan;
    scan.worker = _walk(scan);
    return scan;
  }

  @override
  Future<FileSearchSnapshot> startSearch(
    String deviceId, {
    required String path,
    required String query,
    FileCatalogFilter filter = .all,
  }) async =>
      _startScan(deviceId, path, query: query, filter: filter).searchSnapshot();

  @override
  Future<FileSearchSnapshot> readSearch(
    FileSearchTarget target, {
    int offset = 0,
    int limit = 500,
  }) async {
    _check();
    final scan = _search(target);
    _checkPage(offset, limit);
    return scan.searchSnapshot(offset: offset, limit: limit);
  }

  @override
  Future<void> cancelSearch(FileSearchTarget target) async {
    _check();
    final scan = _search(target);
    scan.cancellation.cancel();
    await scan.worker;
  }

  _Scan _search(FileSearchTarget target) {
    if (target.searchId.isEmpty || target.searchId.contains('\u0000')) {
      throw const FileFailure('invalid_argument', '搜索标识无效。');
    }
    final scan = _findScan(target.deviceId, target.searchId);
    if (scan.gallery) {
      throw const FileFailure('scan_type_mismatch', '此任务不属于文件搜索。');
    }
    if (scan.root != target.path) {
      throw const FileFailure('search_scope_mismatch', '搜索属于另一个目录范围。');
    }
    return scan;
  }

  Future<void> _walk(_Scan scan) async {
    final timer = Timer(const Duration(seconds: 30), () {
      scan.timedOut = true;
      scan.cancellation.cancel();
    });
    final queue = Queue<(String, int)>()..add((scan.root, 0));
    final mediaDirectories = Queue<(String, int)>();
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
      while (mediaDirectories.isNotEmpty || queue.isNotEmpty) {
        scan.cancellation.check();
        final inMediaDirectory = mediaDirectories.isNotEmpty;
        final (path, depth) = (inMediaDirectory ? mediaDirectories : queue)
            .removeFirst();
        scan.currentDirectory = path;
        scan.visitedDirectories = directories + 1;
        if (++directories > (scan.gallery ? 4096 : 2048)) {
          scan.limited = true;
          break;
        }
        FileDirectoryFacts facts;
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
          final child = entry.path;
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
              final preferred =
                  inMediaDirectory ||
                  scan.gallery &&
                      depth == 0 &&
                      const {'DCIM', 'Pictures', 'Movies'}.contains(entry.name);
              (preferred ? mediaDirectories : queue).add((child, depth + 1));
            } else {
              scan.limited = true;
              scan.issue(child, 'depth_limit', '已达到32层目录深度。');
            }
          }
          if (scan.gallery
              ? fact.stamp?.isFile == true &&
                    (entry.mime.startsWith('image/') ||
                        entry.mime.startsWith('video/'))
              : entry.name.toLowerCase().contains(scan.query.toLowerCase()) &&
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
        if (!_closed &&
            DateTime.now().difference(scan.lastProgress).inMilliseconds >=
                200) {
          scan.lastProgress = DateTime.now();
          _changed(scan);
        }
        if (scan.visited > 50000 ||
            scan.entries.length >= (scan.gallery ? 25000 : 500) ||
            bytes > 8 * 1024 * 1024) {
          break;
        }
      }
      scan.status = scan.limited || scan.issues.isNotEmpty
          ? .partial
          : .completed;
    } on FileFailure catch (e) {
      if (e.code == 'cancelled') {
        scan.status = scan.timedOut ? .partial : .cancelled;
      } else {
        scan.issue(scan.root, e.code, e.message);
        scan.status = .failed;
      }
    } catch (e) {
      scan.issue(scan.root, 'scan_failed', '$e');
      scan.status = .failed;
    } finally {
      timer.cancel();
      scan.checkedAt = DateTime.now();
      if (scan.gallery) {
        scan.entries.sort((a, b) {
          final modified = (b.modified ?? 0).compareTo(a.modified ?? 0);
          return modified != 0 ? modified : a.path!.compareTo(b.path!);
        });
      }
      if (!_closed) {
        _changed(scan);
      }
    }
  }

  void _changed(_Scan scan) => _events.add(
    scan.gallery
        ? GalleryScanChanged((deviceId: scan.device, scanId: scan.id))
        : FileSearchChanged((
            deviceId: scan.device,
            searchId: scan.id,
            path: scan.root,
          )),
  );

  _Scan _findScan(String device, String id) {
    final scan = _scans[id];
    if (scan == null) throw const FileFailure('search_not_found', '搜索记录已过期。');
    if (scan.device != device) {
      throw const FileFailure('search_device_mismatch', '搜索属于另一台设备。');
    }
    return scan;
  }

  void _checkPage(int offset, int limit) {
    if (offset < 0 || limit < 1 || limit > 500) {
      throw const FileFailure('invalid_argument', '分页参数无效。');
    }
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
  final String id, device, root, query;
  final FileCatalogFilter filter;
  final bool gallery;
  final cancellation = FileCancellation();
  final entries = <FileCatalogEntry>[];
  final issues = <FileCatalogIssue>[];
  final startedAt = DateTime.now();
  DateTime lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? checkedAt;
  FileSearchStatus status = .running;
  int visited = 0, visitedDirectories = 0;
  String currentDirectory = '';
  bool limited = false, timedOut = false;
  Future<void> worker = Future.value();
  void issue(String path, String code, String reason) {
    if (issues.length < 128) {
      issues.add(FileCatalogIssue(path: path, code: code, reason: reason));
    }
  }

  FileSearchSnapshot searchSnapshot({int offset = 0, int limit = 500}) =>
      FileSearchSnapshot(
        deviceId: device,
        searchId: id,
        path: root,
        query: query,
        filter: filter,
        status: status,
        startedAt: startedAt,
        checkedAt: checkedAt,
        entries: List.unmodifiable(entries.skip(offset).take(limit)),
        issues: List.unmodifiable(issues),
        visitedEntries: visited,
        visitedDirectories: visitedDirectories,
        currentDirectory: currentDirectory,
        total: entries.length,
        hasMore: offset + limit < entries.length,
        limited: limited || timedOut,
      );

  GalleryScanSnapshot gallerySnapshot({int offset = 0, int limit = 100}) {
    final ready = status != .running;
    final page = List<FileCatalogEntry>.unmodifiable(
      entries.skip(offset).take(limit),
    );
    return GalleryScanSnapshot(
      deviceId: device,
      scanId: id,
      status: switch (status) {
        .unknown => .unknown,
        .running => .scanning,
        .completed => .completed,
        .partial || .failed => .partial,
        .cancelled => .cancelled,
      },
      startedAt: startedAt,
      checkedAt: checkedAt,
      items: page,
      issues: List.unmodifiable(issues),
      scope: GalleryScanScope(
        roots: [root],
        excluded: const [
          '/sdcard/Android/data',
          '/sdcard/Android/obb',
          '应用私有目录、其他用户和存储卷',
        ],
      ),
      total: entries.length,
      offset: offset,
      nextOffset: ready && offset + page.length < entries.length
          ? offset + page.length
          : null,
      visitedEntries: visited,
      visitedDirectories: visitedDirectories,
      currentDirectory: currentDirectory,
      limited: limited || timedOut,
    );
  }
}
