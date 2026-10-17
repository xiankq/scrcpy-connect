import 'remote_control_intent.dart';

/// A transient, explicit request to create a stream. It contains no widget,
/// authorization, or persistent trust. Restoring a URL cannot recreate it.
class RemoteLaunchIntent {
  const RemoteLaunchIntent({this.action});
  final RemoteControlIntent? action;
}
