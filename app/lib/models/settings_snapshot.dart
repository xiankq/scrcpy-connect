import 'dart:convert';

Map<String, Object?> _freeze(Map<String, Object?> value) => Map.unmodifiable({
  for (final entry in value.entries)
    entry.key: entry.value is Map
        ? _freeze(Map<String, Object?>.from(entry.value as Map))
        : entry.value,
});

class SettingsSnapshot {
  SettingsSnapshot(this.revision, Map<String, Object?> values)
    : values = _freeze(values);
  final int revision;
  final Map<String, Object?> values;
  Map<String, Object?> toMap() =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(values)) as Map);
}
