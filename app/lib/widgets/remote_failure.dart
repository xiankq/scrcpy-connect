import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

String remoteFailure(
  Object error, {
  String fallback = '手机屏幕操作未完成。请检查手机连接后重试。',
}) {
  if (error is MissingPluginException) return '当前平台尚未提供实时画面，请在手机上继续处理。';
  return failureMessage(error, fallback: fallback);
}

String? remoteFailureCode(Object error) => switch (error) {
  RequestFailure(:final code) => code,
  PlatformException(:final code) => code,
  _ => null,
};
