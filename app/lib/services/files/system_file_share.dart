import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

bool get supportsSystemFileShare =>
    defaultTargetPlatform != TargetPlatform.linux;
bool get supportsSystemDocumentSave => const {
  TargetPlatform.android,
  TargetPlatform.linux,
}.contains(defaultTargetPlatform);

/// 完整原件在系统接收应用读取期间继续受到暂存保护。
Future<String> sharePreparedFile(
  BuildContext context,
  AppController controller,
  String localPath,
) async {
  if (!supportsSystemFileShare) {
    throw const RequestFailure(
      'platform_unavailable',
      '此系统不支持文件分享，请选择保存到系统位置。',
    );
  }
  await controller.execute(ApplicationCommand.mediaCacheRetain, {
    'localPath': localPath,
    'ifManaged': true,
  });
  if (!context.mounted) return '原文件已保留，请返回传输详情继续分享。';
  final render = context.findRenderObject();
  final origin = render is RenderBox && render.hasSize
      ? render.localToGlobal(Offset.zero) & render.size
      : null;
  final result = await SharePlus.instance.share(
    ShareParams(files: [XFile(localPath)], sharePositionOrigin: origin),
  );
  return switch (result.status) {
    ShareResultStatus.success => '已交给系统选择的应用，请在接收应用核对。',
    ShareResultStatus.dismissed => '已关闭系统分享，原文件暂存仍保留。',
    ShareResultStatus.unavailable => '系统没有提供分享结果，请在接收应用核对；不会自动重复分享。',
  };
}
