import 'preferences.dart';

export 'preferences.dart';

abstract interface class SettingsManagement {
  Future<Preferences> read();
  Future<Preferences> update(
    PreferenceChanges changes, {
    int? expectedRevision,
  });
}
