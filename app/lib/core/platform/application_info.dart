import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

part 'application_info.freezed.dart';

@freezed
abstract class ApplicationInfo with _$ApplicationInfo {
  const factory ApplicationInfo({
    required String appName,
    required String packageName,
    required String version,
    required String buildNumber,
  }) = _ApplicationInfo;
}

/// 异步读取期间关闭的应用不能接收迟到的安装包信息。
Future<ApplicationInfo> readApplicationInfo({
  required bool Function() isClosed,
}) async {
  void check() {
    if (isClosed()) throw const RequestFailure('disposed', '应用会话已关闭。');
  }

  check();
  // 读取实际安装包元数据，沿用构建时版本，不在 Rust 或 Dart 另存一份版本号。
  final PackageInfo info;
  try {
    info = await PackageInfo.fromPlatform();
  } on PlatformException catch (error, stack) {
    Error.throwWithStackTrace(
      RequestFailure(
        'application_info_unavailable',
        '无法读取当前安装包信息，请重新启动应用后重试。',
        {'platformCode': error.code},
      ),
      stack,
    );
  } on MissingPluginException catch (_, stack) {
    Error.throwWithStackTrace(
      const RequestFailure(
        'application_info_unavailable',
        '当前宿主尚未提供安装包信息，请重新启动应用后重试。',
      ),
      stack,
    );
  }
  check();
  if (info.version.isEmpty) {
    throw const RequestFailure(
      'application_info_unavailable',
      '当前安装包没有可核实的版本信息。',
    );
  }
  return ApplicationInfo(
    appName: info.appName,
    packageName: info.packageName,
    version: info.version,
    buildNumber: info.buildNumber,
  );
}
