import 'package:scrcpy_connect/models/gallery_history_entry.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

/// 仅保留本进程同设备已核验的相册集合，不保存授权或恢复扫描。
class GalleryStore {
  final _entries = <String, GalleryHistoryEntry>{};

  GalleryHistoryEntry? read(Json device) {
    final entry = _entries[value(device, 'id')];
    return entry != null && entry.matches(device) ? entry : null;
  }

  void save(Json device, Json result, List<Json> items, double offset) {
    final id = value(device, 'id');
    if (id.isEmpty || result['deviceId'] != id) return;
    _entries.remove(id);
    while (_entries.length >= 8) {
      _entries.remove(_entries.keys.first);
    }
    _entries[id] = GalleryHistoryEntry(
      device: device,
      result: result,
      items: items,
      scrollOffset: offset,
    );
  }

  void clear() => _entries.clear();
}
