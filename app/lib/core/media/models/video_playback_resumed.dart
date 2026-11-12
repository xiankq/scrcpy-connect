import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';

final class VideoPlaybackResumed extends AppEvent {
  const VideoPlaybackResumed(this.receipt);
  final VideoPlaybackReceipt receipt;
  @override
  String get type => 'session.output.resumed';
  @override
  String get deviceId => receipt.session.deviceId;
}
