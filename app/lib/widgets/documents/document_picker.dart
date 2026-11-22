import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/files/models/document_selection.dart';

/// 只打开系统选择器；复制、准入和资源清理仍由数据任务拥有。
abstract final class DocumentPicker {
  static const _channel = MethodChannel('dev.scrcpyconnect/platform');

  static Future<String?> pickLocalDirectory({
    required String dialogTitle,
  }) async {
    final directory = await FilePicker.pickDirectory(dialogTitle: dialogTitle);
    return directory?.toFilePath();
  }

  static Future<DocumentSelectionResult> choose(
    DocumentSelectionRequest selection,
  ) async {
    if (selection.mode == .desktopExport) {
      final name = selection.name!;
      final parent = await pickLocalDirectory(dialogTitle: '选择保存 $name 的位置');
      return parent == null
          ? const DocumentSelectionCancelled()
          : DocumentDestinationSelected(p.join(parent, name));
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'documents.platform.picker',
      selection.toJson(),
    );
    return result == null
        ? const DocumentSelectionCancelled()
        : DocumentSelectionResult.fromJson(result);
  }
}
