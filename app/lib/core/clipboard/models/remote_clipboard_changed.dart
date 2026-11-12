import 'package:scrcpy_connect/core/clipboard/models/clipboard_capture.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';

final class RemoteClipboardChanged extends AppEvent {
  const RemoteClipboardChanged({
    required this.deviceId,
    required this.connectionId,
    required this.sessionId,
    required this.capture,
    required this.text,
  });
  @override
  final String deviceId;
  final String connectionId, sessionId, text;
  final ClipboardCapture capture;

  @override
  String get type => 'clipboard.changed';
}
