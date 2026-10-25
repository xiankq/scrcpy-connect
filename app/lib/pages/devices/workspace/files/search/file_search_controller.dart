import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 持有文件搜索页面的加载、错误及轮询状态；替换时只取消原搜索身份。
/// 实际文件搜索由 FileCatalog 执行。
class FileSearchController extends ChangeNotifier {
  FileSearchController(this._execute, this.deviceId);
  final ApplicationCommandExecutor _execute;
  final String deviceId;
  String? _activePath;
  Json? result;
  String? error;
  bool starting = false;
  bool stopping = false;
  bool _disposed = false;
  int _generation = 0;
  int _readGeneration = 0;
  Timer? _poll;
  String? get searchId => result?['searchId'] as String?;
  bool get running => starting || result?['status'] == 'running';

  Future<void> start(
    String query,
    String filter, {
    required String path,
  }) async {
    final previous = result;
    final generation = ++_generation;
    _poll?.cancel();
    if (previous?['status'] == 'running') {
      unawaited(_retire(value(previous!, 'searchId')));
    }
    result = null;
    error = null;
    _activePath = path;
    starting = true;
    stopping = false;
    notifyListeners();
    try {
      final next = await _execute(ApplicationCommand.filesSearchStart, {
        'deviceId': deviceId,
        'path': path,
        'query': query,
        'filter': filter,
      });
      final id = value(next, 'searchId');
      if (next['deviceId'] != deviceId || next['path'] != path || id.isEmpty) {
        throw const RequestFailure('invalid_data', '搜索归属无法核验，请重新搜索。');
      }
      if (_disposed || generation != _generation) {
        await _retire(id);
        return;
      }
      result = next;
      starting = false;
      notifyListeners();
      await _refresh(generation, id);
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        starting = false;
        error = '$failure';
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final id = searchId;
    if (id != null) await _refresh(_generation, id);
  }

  Future<void> _refresh(int generation, String id) async {
    final readGeneration = ++_readGeneration;
    _poll?.cancel();
    try {
      final next = await _execute(ApplicationCommand.filesSearchGet, {
        'deviceId': deviceId,
        'searchId': id,
      });
      if (_disposed ||
          generation != _generation ||
          readGeneration != _readGeneration) {
        return;
      }
      if (next['searchId'] != id ||
          next['deviceId'] != deviceId ||
          next['path'] != _activePath) {
        throw const RequestFailure('invalid_data', '搜索结果归属无法核验，未显示其他范围的内容。');
      }
      result = next;
      error = null;
      if (!running) stopping = false;
      notifyListeners();
      if (running) {
        _poll = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(_refresh(generation, id)),
        );
      }
    } catch (failure) {
      if (!_disposed &&
          generation == _generation &&
          readGeneration == _readGeneration) {
        error = '$failure';
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    final id = searchId;
    if (id == null || !running || stopping) return;
    final generation = _generation;
    stopping = true;
    error = null;
    notifyListeners();
    try {
      await _execute(ApplicationCommand.filesSearchCancel, {
        'deviceId': deviceId,
        'searchId': id,
      });
      if (!_disposed && generation == _generation) {
        await _refresh(generation, id);
      }
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        stopping = false;
        error = '停止搜索未确认：$failure';
        notifyListeners();
      }
    }
  }

  Future<void> _retire(String id) async {
    if (id.isEmpty) return;
    try {
      await _execute(ApplicationCommand.filesSearchCancel, {
        'deviceId': deviceId,
        'searchId': id,
      });
    } catch (_) {
      // 只读任务有后端截止时间，离页不会重试写入。
    }
  }

  @override
  void dispose() {
    final previous = result;
    _disposed = true;
    _generation++;
    _poll?.cancel();
    if (previous?['status'] == 'running') {
      unawaited(_retire(value(previous!, 'searchId')));
    }
    super.dispose();
  }
}
