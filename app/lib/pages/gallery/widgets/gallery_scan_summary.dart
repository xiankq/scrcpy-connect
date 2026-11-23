import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class GalleryScanSummary extends StatelessWidget {
  const GalleryScanSummary({
    super.key,
    required this.scan,
    required this.reading,
    required this.onRestart,
    required this.onCancel,
    required this.onRefresh,
    this.onUpdate,
  });

  final GalleryScanState scan;
  final bool reading;
  final VoidCallback onRestart;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final data = scan.result;
    final checked = data?.status == .scanning && scan.hasUpdate
        ? scan.pendingResult
        : data;
    final status = checked?.status;
    final progress = scan.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scan.showingPrevious)
          Text(
            '上次检查结果 · ${data?.checkedAt?.toIso8601String() ?? data?.startedAt?.toIso8601String() ?? '检查时间未记录'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (scan.hasUpdate)
          TextButton(onPressed: onUpdate, child: const Text('更新照片')),
        if (status != .completed || reading || scan.showingPrevious)
          Text(
            reading
                ? '正在检查手机中的照片与视频'
                : switch (status) {
                    .partial when checked?.limited == true => '只检查了部分文件夹',
                    .partial => '部分文件夹无法读取',
                    .cancelled => '已停止检查',
                    .completed => '已检查共享存储中的照片与视频',
                    _ => '暂时无法读取相册',
                  },
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        if (reading)
          Text(
            '已检查 ${progress?.visitedDirectories ?? 0} 个文件夹、${progress?.visitedEntries ?? 0} 项',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (reading && scan.scanning) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          if (scan.showingPrevious || scan.items.isNotEmpty)
            const ContentLoadingIndicator(),
          TextButton(
            onPressed: scan.scanId == null || scan.stopping ? null : onCancel,
            child: Text(scan.stopping ? '正在停止检查' : '停止检查'),
          ),
        ],
        if (scan.error != null) ...[
          StateNote(scan.error!),
          TextButton(
            onPressed: scan.scanId == null ? onRestart : onRefresh,
            child: const Text('刷新结果'),
          ),
        ],
      ],
    );
  }
}
