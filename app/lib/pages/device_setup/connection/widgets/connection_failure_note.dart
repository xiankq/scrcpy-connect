import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
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
    _failureMessage(failure, pairing: pairing, legacyTcp: legacyTcp),
    icon: LucideIcons.circleAlert,
    color: ConnectTokens.danger,
  );
}

bool connectionAuthorizationRejected(Object? failure) =>
    failure is RequestFailure &&
    (failure.code == 'authorization_required' ||
        RegExp(
          r'received fatal alert: (CertificateRequired|BadCertificate|CertificateUnknown|UnknownCA)\b',
        ).hasMatch(failure.message));

String _failureMessage(
  Object failure, {
  required bool pairing,
  required bool legacyTcp,
}) {
  if (!pairing && !legacyTcp && connectionAuthorizationRejected(failure)) {
    return '手机未授权本机，请重新配对。';
  }
  if (!pairing && failure is RequestFailure && failure.code == 'timeout') {
    return '连接超时，请检查地址、连接端口和网络。';
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
  return '$failure';
}
