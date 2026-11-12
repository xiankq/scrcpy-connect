import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

part 'preferences_state.freezed.dart';

@freezed
class PreferencesState with _$PreferencesState {
  PreferencesState({Preferences? values, this.error})
    : values = values ?? Preferences();
  final Preferences values;
  final String? error;
}
