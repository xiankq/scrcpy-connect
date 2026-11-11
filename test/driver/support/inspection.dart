import 'dart:async';
import 'dart:convert';

import 'cleanup.dart';

/// 逐个核验应用检查点并回执；停止后排空在途核验，设备恢复才可开始。
class DriverInspection {
  DriverInspection({
    required this.request,
    required this.inspect,
    this.key = 'id',
    this.timeout = const Duration(minutes: 5),
    this.stopOnFailure = false,
    this.interval = const Duration(milliseconds: 100),
  }) {
    _pending = _run();
  }

  final Future<Map<String, dynamic>> Function([Map<String, String>? args])
  request;
  final Future<Map<String, Object?>?> Function(Map<String, dynamic>) inspect;
  final String key;
  final Duration timeout;
  final bool stopOnFailure;
  final Duration interval;
  late final Future<void> _pending;
  bool _stopped = false;
  Object? error;

  Future<void> stop() async {
    _stopped = true;
    await _pending;
  }

  Future<void> _run() async {
    String? previous;
    final deadline = DateTime.now().add(timeout);
    try {
      while (!_stopped && DateTime.now().isBefore(deadline)) {
        Map<String, dynamic> response;
        try {
          response = await driverRpc(request());
        } catch (failure) {
          if (_stopped) return;
          final message = failure.toString();
          if (!message.contains('Method not found') &&
              !message.contains('-32601')) {
            rethrow;
          }
          await Future<void>.delayed(interval);
          continue;
        }
        if (_stopped) return;
        final checkpoint = response['checkpoint'];
        if (checkpoint is Map && checkpoint[key] != previous) {
          final data = Map<String, dynamic>.from(checkpoint);
          previous = data[key] as String;
          String? failureMessage;
          Map<String, Object?>? result;
          try {
            result = await inspect(data);
          } catch (failure) {
            error ??= failure;
            failureMessage = failure.toString();
          }
          if (_stopped) return;
          await driverRpc(
            request({
              'ack': previous,
              'error': ?failureMessage,
              if (result != null) 'result': jsonEncode(result),
            }),
          );
          if (failureMessage != null && stopOnFailure) return;
        }
        await Future<void>.delayed(interval);
      }
      if (!_stopped) {
        throw TimeoutException('Driver inspection exceeded $timeout');
      }
    } catch (failure) {
      if (!_stopped) error ??= failure;
    }
  }
}
