import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// One device's read-only scan and its frozen, paged result.
class GalleryScan extends ChangeNotifier {
  GalleryScan(this.controller, this.deviceId);
  final AppController controller;
  final String deviceId;
  Json? result;
  List<Json> items = [];
  String? error;
  bool starting = false;
  bool paging = false;
  bool stopping = false;
  bool _disposed = false;
  int _generation = 0;
  int _read = 0;
  Timer? _poll;
  String? get scanId => result?['scanId'] as String?;
  bool get scanning => starting || result?['status'] == 'scanning';
  int? get nextOffset => result?['nextOffset'] as int?;
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
    result = null;
    items = [];
    error = null;
    notifyListeners();
    try {
      final pending = controller.request('media.list', {
        'deviceId': deviceId,
        'limit': 100,
      });
      // A response after leaving or timing out still owns a backend job.
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
        (scanId != null && scanId != id) ||
        next['offset'] != offset ||
        !const [
          'scanning',
          'completed',
          'partial',
          'cancelled',
        ].contains(status) ||
        (status == 'scanning' && page.isNotEmpty)) {
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
    result = next;
    items = combined;
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
    final id = scanId;
    final offset = nextOffset;
    if (id == null || offset == null || scanning || paging || stopping) return;
    paging = true;
    notifyListeners();
    await _page(id, offset, append: true);
  }

  Future<void> _page(String id, int offset, {required bool append}) async {
    final generation = _generation;
    final read = ++_read;
    _poll?.cancel();
    try {
      final next = await controller
          .request('media.list', {
            'deviceId': deviceId,
            'scanId': id,
            'offset': offset,
            'limit': 100,
          })
          .timeout(const Duration(seconds: 15));
      if (!_current(generation) || read != _read) return;
      _accept(next, offset: offset, append: append);
      paging = false;
      notifyListeners();
      _schedule(generation);
    } catch (failure) {
      if (_current(generation) && read == _read) {
        paging = false;
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
      final next = await controller
          .request('media.scan.cancel', {'deviceId': deviceId, 'scanId': id})
          .timeout(const Duration(seconds: 15));
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

  Future<void> _retire(String id) async {
    if (id.isEmpty) return;
    try {
      await controller
          .request('media.scan.cancel', {'deviceId': deviceId, 'scanId': id})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Read-only work also has a bounded backend deadline.
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
