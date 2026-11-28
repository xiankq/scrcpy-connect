import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/banner.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/progress_bar.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 状态块内各项的间距（Ardot F6 状态 2:4539：间距 12）。
const _gap = DesignTokens.spacingMd;

/// 相册检查状态（Ardot F6 状态 2:4539）：进度条、状态横幅与就地动作。
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
    final colors = AppColors.of(context);
    final note = AppTypography.of(context).footnote
        .copyWith(color: colors.textSecondary);
    final data = scan.result;
    final checked = data?.status == .scanning && scan.hasUpdate
        ? scan.pendingResult
        : data;
    final status = checked?.status;
    final progress = scan.progress;
    final children = <Widget>[
      if (reading &&
          scan.scanning &&
          (scan.showingPrevious || scan.items.isNotEmpty))
        const AppProgressBar(),
      if (scan.showingPrevious)
        Text(
          '上次检查结果 · ${data?.checkedAt?.toIso8601String() ?? data?.startedAt?.toIso8601String() ?? '检查时间未记录'}',
          style: note,
        ),
      if (status != .completed || reading || scan.showingPrevious)
        AppBanner(
          message: reading
              ? '正在检查手机中的照片与视频'
              : switch (status) {
                  .partial when checked?.limited == true => '只检查了部分文件夹',
                  .partial => '部分文件夹无法读取',
                  .cancelled => '已停止检查',
                  .completed => '已检查共享存储中的照片与视频',
                  _ => '暂时无法读取相册',
                },
          icon: reading
              ? LucideIcons.loaderCircle
              : switch (status) {
                  .partial || .cancelled => LucideIcons.circleDashed,
                  .completed => LucideIcons.images,
                  _ => null,
                },
          tone:
              !reading &&
                  status != .completed &&
                  status != .partial &&
                  status != .cancelled
              ? BannerTone.warning
              : BannerTone.info,
        ),
      if (reading)
        Text(
          '已检查 ${progress?.visitedDirectories ?? 0} 个文件夹、${progress?.visitedEntries ?? 0} 项',
          style: note,
        ),
      if (scan.hasUpdate)
        AppButton(
          label: '更新照片',
          role: AppButtonRole.primary,
          size: AppButtonSize.section,
          expand: true,
          onPressed: onUpdate,
        ),
      if (reading && scan.scanning)
        AppButton(
          label: scan.stopping ? '正在停止检查' : '停止检查',
          role: AppButtonRole.secondaryOnPage,
          size: AppButtonSize.section,
          expand: true,
          onPressed: scan.scanId == null || scan.stopping ? null : onCancel,
        ),
      if (scan.error != null) ...[
        StateNote(scan.error!, icon: LucideIcons.circleAlert),
        AppButton(
          label: '刷新结果',
          role: AppButtonRole.secondaryOnPage,
          size: AppButtonSize.section,
          expand: true,
          onPressed: scan.scanId == null ? onRestart : onRefresh,
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(height: _gap),
          child,
        ],
      ],
    );
  }
}
