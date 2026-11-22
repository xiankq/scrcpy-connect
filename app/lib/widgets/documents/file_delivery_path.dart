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
    final theme = Theme.of(context);
    final systemMuted = !staged && systemState == FileDeliveryMilestone.pending;
    final systemColor = switch (systemState) {
      FileDeliveryMilestone.attention => theme.colorScheme.error,
      _ when systemMuted => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.onSurface,
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
          const SizedBox(height: DesignTokens.spacingXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sourceLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Text(
                  '本机暂存',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: staged ? null : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  systemLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: systemColor,
                  ),
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
    final colors = Theme.of(context).colorScheme;
    final (foreground, background) = switch (state) {
      _MilestoneVisual.complete => (
        ConnectTokens.mint,
        ConnectTokens.mint.withValues(alpha: 0.13),
      ),
      _MilestoneVisual.active => (
        ConnectTokens.amber,
        ConnectTokens.amber.withValues(alpha: 0.14),
      ),
      _MilestoneVisual.attention => (colors.error, colors.errorContainer),
      _MilestoneVisual.pending => (
        colors.onSurfaceVariant,
        colors.surfaceContainerHigh,
      ),
    };
    return Container(
      width: DesignTokens.componentIconLargeSize,
      height: DesignTokens.componentIconLargeSize,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(
        icon,
        size: DesignTokens.componentIconSmallSize + 2,
        color: foreground,
      ),
    );
  }
}

class _MilestoneConnector extends StatelessWidget {
  const _MilestoneConnector({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) => Container(
    height: DesignTokens.spacingHairline,
    margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
    color: complete
        ? ConnectTokens.mint.withValues(alpha: 0.48)
        : Theme.of(context).colorScheme.outlineVariant,
  );
}
