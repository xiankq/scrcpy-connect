import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:scrcpy_connect/core/files/file_catalog_entry.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';

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
    required this.onBeginSelect,
    required this.onOpenDirectory,
    this.enabled = true,
  });

  final AppNotifier controller;
  final DeviceSnapshot device;
  final FileCatalogEntry entry;
  final bool grid, selected, selectionActive;
  final bool enabled;
  final ValueChanged<FileCatalogEntry> onSelect, onBeginSelect;
  final ValueChanged<String> onOpenDirectory;

  @override
  Widget build(BuildContext context) {
    final folder = entry.isDirectory;
    final manageable = fileCanManage(entry);
    final openable = fileCanOpen(entry);
    final path = (entry.path ?? '');
    void select() {
      if (manageable) onSelect(entry);
    }

    void open() {
      if (selectionActive) {
        select();
      } else if (enabled && openable) {
        if (folder) {
          onOpenDirectory(path);
        } else {
          FileDetailsRoute(deviceId: device.id, path: path).push<void>(context);
        }
      }
    }

    final onLongPress = manageable ? () => onBeginSelect(entry) : null;
    final Widget tile;
    if (folder) {
      tile = grid
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
    } else {
      tile = grid
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
    return Semantics(
      selected: selectionActive ? selected : null,
      customSemanticsActions: manageable
          ? {
              const CustomSemanticsAction(label: '选择此项'): () =>
                  onBeginSelect(entry),
            }
          : null,
      child: GestureDetector(onSecondaryTap: onLongPress, child: tile),
    );
  }
}
