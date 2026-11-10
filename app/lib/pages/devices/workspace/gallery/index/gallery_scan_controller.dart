import 'package:scrcpy_connect/models/gallery_history_entry.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 持有单设备相册页面的加载、轮询及分页状态；实际扫描由 FileCatalog 执行。
class GalleryScanController extends ChangeNotifier {
  GalleryScanController(
    this._execute,
    this.deviceId, {
    GalleryHistoryEntry? previous,
  }) {
    if (previous != null) {
      result = previous.result;
      items = previous.items;
      showingPrevious = true;
    }
  }
  final ApplicationCommandExecutor _execute;
  final String deviceId;
  Json? result;
  Json? _latest;
  Json? _pendingResult;
  List<Json>? _pendingItems;
  bool showingPrevious = false;
  bool get hasUpdate => _pendingResult != null;
  Json get progress => _latest ?? result ?? {};
  String? _activeScanId;

  List<Json> items = [];
  String? error;
  bool starting = false;
  bool paging = false;
  bool stopping = false;
  bool _disposed = false;
  int _generation = 0;
  int _read = 0;
  int _pagingRead = 0;
  Timer? _poll;
  String? get scanId => _activeScanId;
  bool get scanning => starting || _latest?['status'] == 'scanning';
  int? get nextOffset => result?['nextOffset'] as int?;
  bool get canLoadMore =>
      nextOffset != null &&
      const ['completed', 'partial', 'cancelled'].contains(result?['status']);
  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> start() async {
    if (_disposed) return;
    final old = scanId;
    final generation = ++_generation;
    _poll?.cancel();
    if (old != null) unawaited(_retire(old));
    starting = true;
    paging = false;
    stopping = false;
    _latest = null;
    _activeScanId = null;
    _pendingResult = null;
    _pendingItems = null;
    showingPrevious = result != null;

    error = null;
    notifyListeners();
    try {
      final pending = _execute(ApplicationCommand.mediaList, {
        'deviceId': deviceId,
        'limit': 100,
      });
      // 离页或超时后的迟到回执仍对应需要回收的后端任务。
      unawaited(
        pending.then<void>((next) {
          if (!_current(generation) && next['deviceId'] == deviceId) {
            unawaited(_retire(value(next, 'scanId')));
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final next = await pending.timeout(const Duration(seconds: 15));
      if (!_current(generation)) return;
      _accept(next, offset: 0);
      starting = false;
      notifyListeners();
      _schedule(generation);
    } catch (failure) {
      if (_current(generation)) {
        _generation++;
        starting = false;
        paging = false;
        error = '相册检查未能开始：$failure';
        notifyListeners();
      }
    }
  }

  void _accept(Json next, {required int offset, bool append = false}) {
    final id = value(next, 'scanId');
    final status = value(next, 'status');
    final page = objects(next['items']);
    if (id.isEmpty ||
        next['deviceId'] != deviceId ||
        (append ? (result?['scanId'] != id) : scanId != null && scanId != id) ||
        next['offset'] != offset ||
        (append && status == 'scanning') ||
        !const [
          'scanning',
          'completed',
          'partial',
          'cancelled',
        ].contains(status)) {
      throw const RequestFailure('invalid_data', '相册结果归属或范围无法核验，请重新检查。');
    }
    if (append && items.length != offset) {
      throw const RequestFailure('invalid_data', '相册分页位置已变化，请重新检查。');
    }
    final nextPage = next['nextOffset'];
    if (nextPage != null &&
        (nextPage is! int ||
            nextPage <= offset ||
            nextPage != offset + page.length)) {
      throw const RequestFailure('invalid_data', '相册分页位置无法核验，请重新检查。');
    }
    final combined = [if (append) ...items, ...page];
    final paths = combined.map((file) => value(file, 'path')).toSet();
    if (paths.length != combined.length || paths.contains('')) {
      throw const RequestFailure('invalid_data', '相册分页包含重复或无效项目，请重新检查。');
    }
    if (append) {
      // 分页只扩展当前可见的稳定集合，不接管后台检查或待更新集合。
      result = next;
      items = combined;
      return;
    }
    _activeScanId = id;
    _latest = next;
    if (showingPrevious) {
      if (status != 'scanning') {
        _pendingResult = next;
        _pendingItems = combined;
      }
    } else if (status == 'scanning') {
      // Discovery appends by path; an already visible object never moves.
      final seen = items.map((file) => value(file, 'path')).toSet();
      items = [
        ...items,
        ...page.where((file) => seen.add(value(file, 'path'))),
      ];
      result = next;
    } else if (result?['status'] == 'scanning' &&
        items.isNotEmpty &&
        !listEquals(
          items.map((file) => file['path']).toList(),
          combined.map((file) => file['path']).toList(),
        )) {
      showingPrevious = true;
      _pendingResult = next;
      _pendingItems = combined;
    } else {
      result = next;
      items = combined;
    }
    error = null;
  }

  void _schedule(int generation) {
    if (_current(generation) && scanning && !stopping) {
      _poll = Timer(
        const Duration(milliseconds: 400),
        () => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    final id = scanId;
    if (id == null) return;
    await _page(id, 0, append: false);
  }

  Future<void> loadMore() async {
    final id = result?['scanId'] as String?;
    final offset = nextOffset;
    if (id == null || offset == null || !canLoadMore || paging || stopping) {
      return;
    }
    paging = true;
    notifyListeners();
    await _page(id, offset, append: true);
  }

  Future<void> _page(String id, int offset, {required bool append}) async {
    final generation = _generation;
    final read = append ? ++_pagingRead : ++_read;
    if (!append) _poll?.cancel();
    try {
      final next = await _execute(ApplicationCommand.mediaList, {
        'deviceId': deviceId,
        'scanId': id,
        'offset': offset,
        'limit': 100,
      }).timeout(const Duration(seconds: 15));
      if (!_current(generation) || read != (append ? _pagingRead : _read)) {
        return;
      }
      _accept(next, offset: offset, append: append);
      if (append) paging = false;
      notifyListeners();
      if (!append) _schedule(generation);
    } catch (failure) {
      if (_current(generation) && read == (append ? _pagingRead : _read)) {
        if (append) paging = false;
        error = '相册检查未完成：$failure';
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    final id = scanId;
    if (id == null || !scanning || stopping) return;
    final generation = _generation;
    ++_read;
    _poll?.cancel();
    stopping = true;
    notifyListeners();
    try {
      final next = await _execute(ApplicationCommand.mediaScanCancel, {
        'deviceId': deviceId,
        'scanId': id,
      }).timeout(const Duration(seconds: 15));
      if (!_current(generation)) return;
      _accept(next, offset: 0);
      stopping = false;
      notifyListeners();
    } catch (failure) {
      if (_current(generation)) {
        stopping = false;
        error = '停止检查尚未确认：$failure';
        notifyListeners();
      }
    }
  }

  void applyUpdate() {
    if (_pendingResult == null || _pendingItems == null) return;
    ++_pagingRead;
    paging = false;
    result = _pendingResult;
    items = _pendingItems!;
    _pendingResult = null;
    _pendingItems = null;
    showingPrevious = false;
    notifyListeners();
  }

  Future<void> _retire(String id) async {
    if (id.isEmpty) return;
    try {
      await _execute(ApplicationCommand.mediaScanCancel, {
        'deviceId': deviceId,
        'scanId': id,
      }).timeout(const Duration(seconds: 15));
    } catch (_) {
      // 只读任务也有有界的后端截止时间。
    }
  }

  @override
  void dispose() {
    final id = scanId;
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    if (id != null) unawaited(_retire(id));
    super.dispose();
  }
}
