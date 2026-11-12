import 'package:scrcpy_connect/core/control/models/session_activity.dart';

class RemoteWindowClose {
  const RemoteWindowClose({this.receipt, this.lockFailure, this.closeFailure});
  final VideoStopReceipt? receipt;
  final Object? lockFailure;
  final Object? closeFailure;
}
