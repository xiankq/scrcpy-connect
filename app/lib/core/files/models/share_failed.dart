import 'package:scrcpy_connect/core/events/models/app_event.dart';

final class ShareFailed extends AppEvent {
  const ShareFailed(this.reason);

  final String reason;
  @override
  String get type => 'sharing.failed';
}
