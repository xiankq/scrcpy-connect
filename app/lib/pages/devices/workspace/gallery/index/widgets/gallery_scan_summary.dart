import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import '../gallery_scan_controller.dart';
import 'gallery_scope_sheet.dart';

class GalleryScanSummary extends StatelessWidget {
  const GalleryScanSummary({
    super.key,
    required this.scan,
    required this.device,
    required this.onRestart,
  });

  final GalleryScanController scan;
  final Json device;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final data = scan.result ?? <String, dynamic>{};
    final status = value(data, 'status');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scan.scanning
              ? '正在检查手机中的照片与视频'
              : switch (status) {
                  'partial' => '部分目录未能检查',
                  'cancelled' => '已停止检查',
                  'completed' => '已检查共享存储中的照片与视频',
                  _ => '暂时无法读取相册',
                },
          style: status == 'completed' && !scan.scanning
              ? Theme.of(context).textTheme.bodySmall
              : Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        LayoutBuilder(
          builder: (context, constraints) {
            final details = Text(
              scan.scanning
                  ? '已检查 ${data['visitedDirectories'] ?? 0} 个文件夹、${data['visitedEntries'] ?? 0} 项'
                  : '已显示 ${scan.items.length} / ${data['total'] ?? 0} 项 · 按文件修改时间排列',
              style: Theme.of(context).textTheme.bodySmall,
            );
            if (scan.result == null) return details;
            final scopeAction = TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  DesignTokens.componentIconButtonSize,
                  DesignTokens.componentIconButtonSize,
                ),
              ),
              onPressed: () => showGlassModalSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    GalleryScopeSheet(device: device, snapshot: data),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('相册范围与未读项目')),
                  SizedBox(width: DesignTokens.spacingXs),
                  Icon(
                    LucideIcons.chevronUp,
                    size: DesignTokens.componentIconSmallSize,
                  ),
                ],
              ),
            );
            final scopeLabelWidth = MediaQuery.textScalerOf(
              context,
            ).scale(DesignTokens.typographyLabelFontSize * '相册范围与未读项目'.length);
            if (scopeLabelWidth +
                    DesignTokens.componentIconSmallSize +
                    DesignTokens.spacingLg * 2 >
                constraints.maxWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: scopeAction,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: DesignTokens.spacingSm),
                Flexible(child: scopeAction),
              ],
            );
          },
        ),
        if (scan.scanning) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          const LinearProgressIndicator(minHeight: 2),
          TextButton(
            onPressed: scan.scanId == null || scan.stopping
                ? null
                : scan.cancel,
            child: Text(scan.stopping ? '正在停止检查' : '停止检查'),
          ),
        ],
        if (scan.error != null) ...[
          StateNote(scan.error!),
          TextButton(
            onPressed: scan.scanId == null ? onRestart : scan.refresh,
            child: const Text('重新核验本次检查'),
          ),
        ],
      ],
    );
  }
}
