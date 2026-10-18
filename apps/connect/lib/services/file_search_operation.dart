import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Owns one visible read-only search; replacing it retires only that identity.
class FileSearchOperation extends ChangeNotifier {
  FileSearchOperation(this.controller, this.deviceId, this.path);
  final AppController controller;
  final String deviceId;
  final String path;
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

  Future<void> start(String query, String filter) async {
    final previous = result;
    final generation = ++_generation;
    _poll?.cancel();
    if (previous?['status'] == 'running') {
      unawaited(_retire(value(previous!, 'searchId')));
    }
    result = null;
    error = null;
    starting = true;
    stopping = false;
    notifyListeners();
    try {
      final next = await controller.execute(InteropCommand.filesSearchStart, {
        'deviceId': deviceId,
        'path': path,
        'query': query,
        'filter': filter,
      });
      final id = value(next, 'searchId');
      if (next['deviceId'] != deviceId || id.isEmpty) {
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
      final next = await controller.execute(InteropCommand.filesSearchGet, {
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
          next['path'] != path) {
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
      await controller.execute(InteropCommand.filesSearchCancel, {
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
      await controller.execute(InteropCommand.filesSearchCancel, {
        'deviceId': deviceId,
        'searchId': id,
      });
    } catch (_) {
      // Read-only jobs have a backend deadline. No write is retried on leave.
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
