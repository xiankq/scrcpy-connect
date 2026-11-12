import 'package:scrcpy_connect/core/settings/models/preferences.dart';

export 'package:scrcpy_connect/core/settings/models/preferences.dart';

abstract interface class SettingsManagement {
  Future<Preferences> read();
  Future<Preferences> update(
    PreferenceChanges changes, {
    int? expectedRevision,
  });
}
