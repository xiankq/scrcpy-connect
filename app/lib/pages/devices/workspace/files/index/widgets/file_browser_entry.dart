import 'package:flutter/material.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'file_entry_tiles.dart';

/// 目录项统一处理选择与打开；网格和列表共用同一套准入判断。
class FileBrowserEntry extends StatelessWidget {
  const FileBrowserEntry({
    super.key,
    required this.controller,
    required this.device,
    required this.entry,
    required this.grid,
    required this.selected,
    required this.selectionActive,
    required this.onSelect,
    required this.onOpenDirectory,
  });

  final AppController controller;
  final Json device;
  final Json entry;
  final bool grid, selected, selectionActive;
  final ValueChanged<Json> onSelect;
  final ValueChanged<String> onOpenDirectory;

  @override
  Widget build(BuildContext context) {
    final folder = entry['isDirectory'] == true;
    final manageable = fileCanManage(entry);
    final openable = fileCanOpen(entry);
    final path = value(entry, 'path');
    void select() {
      if (manageable) onSelect(entry);
    }

    void open() {
      if (selectionActive) {
        select();
      } else if (openable) {
        if (folder) {
          onOpenDirectory(path);
        } else {
          FileDetailsRoute(
            deviceId: value(device, 'id'),
            path: path,
          ).push<void>(context);
        }
      }
    }

    final onLongPress = manageable ? select : null;
    if (folder) {
      return grid
          ? FolderGridTile(
              folder: entry,
              selected: selected,
              selectionActive: selectionActive,
              onTap: open,
              onLongPress: onLongPress,
            )
          : FolderListTile(
              folder: entry,
              selected: selected,
              selectionActive: selectionActive,
              onTap: open,
              onLongPress: onLongPress,
            );
    }
    return grid
        ? FileGridTile(
            controller: controller,
            device: device,
            file: entry,
            selected: selected,
            selectionActive: selectionActive,
            onTap: open,
            onLongPress: onLongPress,
          )
        : FileListTile(
            file: entry,
            selected: selected,
            selectionActive: selectionActive,
            onTap: open,
            onLongPress: onLongPress,
          );
  }
}
