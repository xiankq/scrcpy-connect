import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum FileDeliveryMilestone { pending, complete, attention }

class FileDeliveryPath extends StatelessWidget {
  const FileDeliveryPath({
    super.key,
    required this.sourceLabel,
    required this.staged,
    required this.systemState,
    this.systemLabel = '系统副本',
  });

  final String sourceLabel;
  final bool staged;
  final FileDeliveryMilestone systemState;
  final String systemLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final caption = AppTypography.of(context).footnote;
    final systemMuted = !staged && systemState == FileDeliveryMilestone.pending;
    final systemColor = switch (systemState) {
      FileDeliveryMilestone.attention => colors.error,
      _ when systemMuted => colors.textSecondary,
      _ => colors.text,
    };
    final stageActive = !staged;
    return Semantics(
      label:
          '$sourceLabel，${staged ? '已取回本机暂存' : '正在取回本机暂存'}，'
          '$systemLabel${switch (systemState) {
            FileDeliveryMilestone.pending => '尚未开始',
            FileDeliveryMilestone.complete => '已完成',
            FileDeliveryMilestone.attention => '需要核对',
          }}',
      child: Column(
        children: [
          Row(
            children: [
              _MilestoneIcon(
                icon: LucideIcons.smartphone,
                state: _MilestoneVisual.complete,
              ),
              Expanded(child: _MilestoneConnector(complete: staged)),
              _MilestoneIcon(
                icon: AppIcons.download,
                state: staged
                    ? _MilestoneVisual.complete
                    : stageActive
                    ? _MilestoneVisual.active
                    : _MilestoneVisual.pending,
              ),
              Expanded(
                child: _MilestoneConnector(
                  complete: systemState == FileDeliveryMilestone.complete,
                ),
              ),
              _MilestoneIcon(
                icon: systemState == FileDeliveryMilestone.attention
                    ? LucideIcons.circleAlert
                    : LucideIcons.fileOutput,
                state: switch (systemState) {
                  FileDeliveryMilestone.complete => _MilestoneVisual.complete,
                  FileDeliveryMilestone.attention => _MilestoneVisual.attention,
                  FileDeliveryMilestone.pending when staged =>
                    _MilestoneVisual.active,
                  FileDeliveryMilestone.pending => _MilestoneVisual.pending,
                },
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sourceLabel,
                  textAlign: TextAlign.center,
                  style: caption,
                ),
              ),
              Expanded(
                child: Text(
                  '本机暂存',
                  textAlign: TextAlign.center,
                  style: caption.copyWith(
                    color: staged ? colors.text : colors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  systemLabel,
                  textAlign: TextAlign.center,
                  style: caption.copyWith(color: systemColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MilestoneVisual { pending, active, complete, attention }

class _MilestoneIcon extends StatelessWidget {
  const _MilestoneIcon({required this.icon, required this.state});

  final IconData icon;
  final _MilestoneVisual state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // 已完成用成功色，进行中用主色（进度），需核对用错误色，未开始为中性 block 底。
    final (foreground, background) = switch (state) {
      _MilestoneVisual.complete => (colors.success, colors.successContainer),
      _MilestoneVisual.active => (colors.primary, colors.primaryContainer),
      _MilestoneVisual.attention => (colors.error, colors.errorContainer),
      _MilestoneVisual.pending => (colors.textSecondary, colors.block),
    };
    return Container(
      width: DesignTokens.componentSectionButtonSize,
      height: DesignTokens.componentSectionButtonSize,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(
        icon,
        size: DesignTokens.componentSectionGlyphSize,
        color: foreground,
      ),
    );
  }
}

class _MilestoneConnector extends StatelessWidget {
  const _MilestoneConnector({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: DesignTokens.componentSeparatorHeight,
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
      color: complete ? colors.success : colors.separator,
    );
  }
}
