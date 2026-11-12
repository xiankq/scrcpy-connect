import 'dart:collection';

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

// 只有本模块创建的深冻结值可以复用；外部的只读视图仍可能有可变后备集合。
final class _FrozenJson extends UnmodifiableMapView<String, dynamic> {
  _FrozenJson(super.map);
}

final class _FrozenList<T> extends UnmodifiableListView<T> {
  _FrozenList(super.source);
}

Object? _freeze(Object? value) => switch (value) {
  _FrozenJson() || _FrozenList<Object?>() => value,
  Map<Object?, Object?> map => _FrozenJson({
    for (final entry in map.entries)
      if (entry.key case final String key) key: _freeze(entry.value),
  }),
  List<Object?> list => _FrozenList(list.map(_freeze).toList(growable: false)),
  _ => value,
};
Map<String, dynamic> immutableJson(Map<String, dynamic> value) =>
    value is _FrozenJson
    ? value
    : _FrozenJson({
        for (final entry in value.entries) entry.key: _freeze(entry.value),
      });

/// 深冻结记录列表，并复用本模块已冻结的值，保持未改变投影的身份。
List<Map<String, dynamic>> immutableJsonRecords(
  List<Map<String, dynamic>> records,
) => records is _FrozenList<Map<String, dynamic>>
    ? records
    : _FrozenList(records.map(immutableJson).toList(growable: false));
