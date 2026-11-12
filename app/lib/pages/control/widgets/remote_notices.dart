import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show glassSnackBar;

/// 提示的去重、排队和可见性由远控视图持有；会话只提供当前状态。
final class RemoteNotices {
  RemoteNotices({required this.presentation, required this.isVisible});
  final RemotePresentation presentation;
  final bool Function() isVisible;
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  RemoteBinding? _binding;
  (String, String)? _errorKey;
  String? _pending;
  bool _scheduled = false;
  bool _disposed = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _tail;

  void show(String message) {
    if (_disposed) return;
    final notice = messengerKey.currentState?.showSnackBar(
      glassSnackBar(message),
    );
    if (notice == null) return;
    _tail = notice;
    unawaited(
      notice.closed.then((_) {
        if (_disposed) return;
        if (identical(_tail, notice)) _tail = null;
        flush();
      }),
    );
  }

  void consume(Json receipt) {
    if (_disposed ||
        presentation.exiting ||
        !receipt.containsKey('keepActiveError')) {
      return;
    }
    final binding = presentation.binding;
    if (_binding != binding) {
      _binding = binding;
      _errorKey = null;
      _pending = null;
    }
    if (receipt['keepActiveError'] == null) {
      _errorKey = null;
      _pending = null;
      return;
    }
    final error = jsonObject(receipt['keepActiveError']);
    final reason = value(error, 'reason', '保持唤醒服务未能确认。');
    final key = (value(error, 'code'), reason);
    if (_errorKey == key) return;
    _errorKey = key;
    _pending = '保持唤醒尚未确认：$reason';
    flush();
  }

  void flush() {
    if (_disposed || _pending == null || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || presentation.exiting) return;
      if (_binding != presentation.binding) {
        _pending = null;
        return;
      }
      if (!isVisible() ||
          presentation.covered ||
          presentation.stateUnverified ||
          presentation.sessionEnded) {
        return;
      }
      final message = _pending;
      // 未展示的提示留在本队列，前一条结束后重新核对绑定，避免旧提示排进 SnackBar 队列。
      if (messengerKey.currentState == null ||
          message == null ||
          _tail != null) {
        return;
      }
      _pending = null;
      show(message);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _tail = null;
  }
}
