import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_request.dart';

/// 只打开系统选择器；复制、准入和资源清理仍由数据任务拥有。
abstract final class DocumentPicker {
  static const _channel = MethodChannel('dev.scrcpyconnect/platform');

  static Future<Json> choose(Json selection) async {
    if (selection['mode'] == 'desktopExport') {
      final name = selection['name'] as String;
      final parent = await FilePicker.getDirectoryPath(
        dialogTitle: '选择保存 $name 的位置',
      );
      return parent == null
          ? {'status': 'cancelled'}
          : {'status': 'selected', 'destination': p.join(parent, name)};
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'documents.platform.picker',
      selection,
    );
    return result ?? {'status': 'cancelled'};
  }
}
