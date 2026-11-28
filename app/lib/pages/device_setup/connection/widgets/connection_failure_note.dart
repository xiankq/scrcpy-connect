import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 保留原始请求失败，同时提供可操作的表单反馈。
class ConnectionFailureNote extends StatelessWidget {
  const ConnectionFailureNote({
    super.key,
    required this.failure,
    required this.pairing,
    required this.legacyTcp,
  });

  final Object failure;
  final bool pairing;
  final bool legacyTcp;

  @override
  Widget build(BuildContext context) => StateNote(
    connectionFailureMessage(failure, pairing: pairing, legacyTcp: legacyTcp),
    icon: LucideIcons.circleAlert,
    color: AppColors.of(context).error,
  );
}

bool connectionAuthorizationRejected(Object? failure) =>
    failure is RequestFailure &&
    (failure.code == 'authorization_required' ||
        RegExp(
          r'received fatal alert: (CertificateRequired|BadCertificate|CertificateUnknown|UnknownCA)\b',
        ).hasMatch(failure.message));

String connectionFailureMessage(
  Object failure, {
  required bool pairing,
  required bool legacyTcp,
}) {
  if (!pairing && !legacyTcp && connectionAuthorizationRejected(failure)) {
    return '手机未授权本机，请重新配对。';
  }
  if (failure is RequestFailure && failure.code == 'timeout') {
    return pairing
        ? '手机没有及时响应。请重新打开配对窗口，使用新显示的端口和配对码。'
        : '手机没有及时响应。请核对地址和端口，确认两台设备连着同一 Wi-Fi。';
  }
  if (pairing &&
      failure is RequestFailure &&
      failure.message.toLowerCase().contains('pairing authentication failed')) {
    return '配对失败，请使用手机当前显示的配对端口和配对码。';
  }
  if (pairing &&
      failure is RequestFailure &&
      (failure.code == 'disconnected' ||
          RegExp(
            r'\b(eof|end of file)\b',
            caseSensitive: false,
          ).hasMatch(failure.message))) {
    return '配对中断，请确认手机配对窗口仍开启，然后重试。';
  }
  return failureMessage(
    failure,
    fallback: pairing
        ? '无法完成配对。请打开手机的配对窗口，核对端口和配对码。'
        : '无法连接手机。请确认两台设备连着同一 Wi-Fi，再核对地址和端口。',
  );
}
