import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

final class SettingsChanged extends AppEvent {
  const SettingsChanged(this.preferences);
  final Preferences preferences;
  @override
  String get type => 'settings.changed';
}
