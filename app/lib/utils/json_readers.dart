Map<String, dynamic> jsonObject(Object? value) => value is Map<Object?, Object?>
    ? {
        for (final entry in value.entries)
          if (entry.key case final String key) key: entry.value,
      }
    : <String, dynamic>{};
List<String> strings(Object? value) =>
    value is List<Object?> ? value.whereType<String>().toList() : <String>[];
List<Object?> values(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];
List<Map<String, dynamic>> objects(Object? value) => value is List<Object?>
    ? value.whereType<Map<Object?, Object?>>().map(jsonObject).toList()
    : <Map<String, dynamic>>[];
String value(Map<String, dynamic> data, String key, [String fallback = '']) =>
    data[key]?.toString() ?? fallback;
Object? _freeze(Object? value) => switch (value) {
  Map<Object?, Object?> map => Map<String, dynamic>.unmodifiable({
    for (final entry in map.entries)
      if (entry.key case final String key) key: _freeze(entry.value),
  }),
  List<Object?> list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};
Map<String, dynamic> immutableJson(Map<String, dynamic> value) =>
    Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    });
