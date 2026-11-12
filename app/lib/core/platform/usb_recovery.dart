import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:scrcpy_connect/core/application/request_failure.dart';

/// 先封存旧 USB 准入，再由宿主排空 SDK，最后确认平台原始描述符实际回收。
/// 同一对象的失败重试保持原候选；不会按 ready 跳过恢复或用超时丢弃在途调用。
final class UsbRecovery {
  UsbRecovery({
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
    platform,
  }) : _platform = platform ?? _request;

  static const _channel = MethodChannel('dev.scrcpyconnect/platform');
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _platform;
  String? _expectedLease, _candidate;
  bool _begun = false, _completed = false;
  Future<void>? _beginning, _completing;

  /// 只有 complete 得到实际成功回执后才可把权限交给平台操作实例。
  String get ownerLeaseId {
    if (!_completed) throw StateError('USB 资源尚未完成恢复。');
    return _candidate!;
  }

  /// 幂等封存；返回后调用方必须先排空旧 SDK 握手、连接和文件描述符副本。
  Future<void> begin() {
    if (_begun) return Future.value();
    return _beginning ??= Future<void>.microtask(_begin).whenComplete(() {
      _beginning = null;
    });
  }

  Future<void> _begin() async {
    if (_candidate == null) {
      final environment = await _platform('usb.environment', const {});
      final Object? previous = environment['ownerLeaseId'];
      if (environment['ownerReady'] is! bool ||
          environment['ownerReady'] == true && previous == null ||
          previous != null && !_validLease(previous)) {
        _unconfirmed('USB 平台没有提供有效的原权限事实。');
      }
      _expectedLease = previous as String?;
      final random = Random.secure();
      String candidate;
      do {
        candidate = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      } while (candidate == previous);
      _candidate = candidate;
    }
    final response = await _platform('usb.beginRecovery', {
      'expectedOwnerLeaseId': _expectedLease,
      'ownerLeaseId': _candidate,
    });
    if (response['begun'] != true ||
        response['ownerReady'] is! bool ||
        response['ownerLeaseId'] != _candidate) {
      _unconfirmed('USB 平台尚未确认旧准入已封存。');
    }
    _begun = true;
  }

  /// 只在 SDK 已实际排空后调用；平台确认回收前，不交付新权限。
  Future<void> complete() {
    if (!_begun) throw StateError('必须先完成 USB begin，再排空 SDK。');
    if (_completed) return Future.value();
    return _completing ??= Future<void>.microtask(_complete).whenComplete(() {
      _completing = null;
    });
  }

  Future<void> _complete() async {
    final response = await _platform('usb.completeRecovery', {
      'ownerLeaseId': _candidate,
    });
    if (response['completed'] != true ||
        response['ownerReady'] != true ||
        response['ownerLeaseId'] != _candidate) {
      _unconfirmed('USB 原始资源回收尚未确认，请使用原候选重试。');
    }
    _completed = true;
  }

  static Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _channel.invokeMethod<Object?>(command, params);
      if (response is! Map<Object?, Object?>) {
        _unconfirmed('USB 平台没有返回恢复回执。');
      }
      return Map<String, dynamic>.from(response);
    } on PlatformException catch (error) {
      throw RequestFailure(
        error.code,
        error.message ?? 'USB 资源恢复尚未确认。',
        error.details,
      );
    }
  }
}

Never _unconfirmed(String message) =>
    throw RequestFailure('usb_cleanup_unconfirmed', message);

bool _validLease(Object value) =>
    value is String &&
    value.length <= 256 &&
    value.trim().isNotEmpty &&
    !value.runes.any((code) => code < 32 || code >= 127 && code <= 159);
