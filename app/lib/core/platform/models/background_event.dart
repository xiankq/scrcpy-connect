import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/platform/models/background_status.dart';

sealed class BackgroundEvent extends AppEvent {
  const BackgroundEvent();

  @override
  String get type => switch (this) {
    BackgroundChanged() => 'background.changed',
    BackgroundFailed() => 'background.failed',
  };
}

final class BackgroundChanged extends BackgroundEvent {
  const BackgroundChanged(this.status);
  final BackgroundStatus status;
}

final class BackgroundFailed extends BackgroundEvent {
  const BackgroundFailed(this.reason);
  final String reason;
}
