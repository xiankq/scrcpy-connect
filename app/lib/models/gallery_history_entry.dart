import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

class GalleryHistoryEntry {
  GalleryHistoryEntry({
    required Json device,
    required Json result,
    required List<Json> items,
    required this.scrollOffset,
  }) : device = immutableJson(device),
       result = immutableJson(result),
       items = List.unmodifiable(items.map(immutableJson));

  final Json device, result;
  final List<Json> items;
  final double scrollOffset;

  bool matches(Json record) =>
      device['id'] == record['id'] &&
      device['guid'] == record['guid'] &&
      device['serial'] == record['serial'];
}
