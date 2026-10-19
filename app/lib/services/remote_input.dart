import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:math' as math;

import 'package:flutter/services.dart';

String remoteFailure(Object error) {
  if (error is PlatformException) {
    final message = error.message;
    if (message != null && RegExp(r'[\u4e00-\u9fff]').hasMatch(message)) {
      return message;
    }
    return '实时画面操作未完成。请检查设备连接后重新尝试。';
  }
  if (error is MissingPluginException) return '当前平台尚未提供实时画面，请在手机上继续处理。';
  return '$error';
}

String? remoteFailureCode(Object error) => switch (error) {
  RequestFailure(:final code) => code,
  PlatformException(:final code) => code,
  _ => null,
};

/// Maps pointer positions only inside the contained source frame, never the
/// letterbox bars or controller controls.
Offset? sourcePoint(
  Offset local,
  Size viewport,
  Size source, {
  bool clamp = false,
}) {
  if (source.isEmpty || viewport.isEmpty) return null;
  final scale = math.min(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  final origin = Offset(
    (viewport.width - source.width * scale) / 2,
    (viewport.height - source.height * scale) / 2,
  );
  final point = (local - origin) / scale;
  if (clamp) {
    return Offset(
      point.dx.clamp(0, source.width - 1),
      point.dy.clamp(0, source.height - 1),
    );
  }
  if (point.dx < 0 ||
      point.dy < 0 ||
      point.dx >= source.width ||
      point.dy >= source.height) {
    return null;
  }
  return point;
}
