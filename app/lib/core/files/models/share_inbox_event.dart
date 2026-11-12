import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';

sealed class ShareInboxEvent extends AppEvent {
  const ShareInboxEvent();
}

final class ShareReceived extends ShareInboxEvent {
  const ShareReceived(this.share);
  final IncomingShare share;

  @override
  String get type => 'share.received';
}

final class ShareConsumed extends ShareInboxEvent {
  const ShareConsumed(this.shareId);
  final String shareId;

  @override
  String get type => 'share.consumed';
}
