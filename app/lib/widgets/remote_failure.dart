import 'package:flutter/services.dart';

import 'package:scrcpy_connect/core/application/request_failure.dart';

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
