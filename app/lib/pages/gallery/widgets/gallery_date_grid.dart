import 'dart:math' as math;

import 'package:flutter/rendering.dart' show SliverGridRegularTileLayout;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/gallery/widgets/gallery_media_tile.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// Keep one lazy viewport for both date headings and thumbnail rows.
class GalleryDateGrid extends HookWidget {
  const GalleryDateGrid({
    super.key,
    required this.device,
    required this.entries,
    required this.delegate,
    required this.selected,
    required this.onTap,
  });

  final DeviceSnapshot device;
  final List<FileCatalogEntry> entries;
  final SliverGridDelegateWithMaxCrossAxisExtent delegate;
  final Set<String> selected;
  final ValueChanged<FileCatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final groups = useMemoized(() {
      final days = <DateTime?, List<FileCatalogEntry>>{};
      for (final file in entries) {
        final seconds = file.modified;
        final day = seconds == null || seconds <= 0
            ? null
            : DateUtils.dateOnly(
                DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
              );
        days.putIfAbsent(day, () => []).add(file);
      }
      return days;
    }, [entries]);
    final year = DateTime.now().year;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final layout =
            delegate.getLayout(constraints) as SliverGridRegularTileLayout;
        final columns = layout.crossAxisCount;
        return HookBuilder(
          builder: (context) {
            final rows = useMemoized(
              () => [
                for (final MapEntry(key: date, value: files)
                    in groups.entries) ...[
                  (day: date, start: 0, files: const <FileCatalogEntry>[]),
                  for (var start = 0; start < files.length; start += columns)
                    (day: date, start: start, files: files),
                ],
              ],
              [groups, columns],
            );
            return SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row.files.isEmpty) {
                  final day = row.day;
                  return Padding(
                    padding: const EdgeInsets.only(
                      top: DesignTokens.spacingSm,
                      bottom: DesignTokens.spacingXs,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        day == null
                            ? '日期未知'
                            : '${day.year == year ? '' : '${day.year} 年 '}${day.month} 月 ${day.day} 日',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  );
                }
                final end = math.min(row.files.length, row.start + columns);
                return Padding(
                  padding: EdgeInsets.only(
                    top: row.start == 0 ? 0 : delegate.mainAxisSpacing,
                  ),
                  child: Row(
                    children: [
                      for (var i = row.start; i < end; i++) ...[
                        if (i > row.start)
                          SizedBox(width: delegate.crossAxisSpacing),
                        SizedBox.square(
                          dimension: layout.childCrossAxisExtent,
                          child: GalleryMediaTile(
                            key: ValueKey(row.files[i].path),
                            file: row.files[i],
                            device: device,
                            selected: selected.contains(row.files[i].path),
                            onTap: () => onTap(row.files[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
