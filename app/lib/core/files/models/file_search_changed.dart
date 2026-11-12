import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/files/models/file_search_snapshot.dart';

/// 查询失效事实；结果仍由原搜索任务提供。
final class FileSearchChanged extends AppEvent {
  const FileSearchChanged(this.target);
  final FileSearchTarget target;

  @override
  String get type => 'files.search.changed';

  @override
  String get deviceId => target.deviceId;
}
