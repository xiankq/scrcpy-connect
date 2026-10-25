import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

class RemoteNavigationBar extends StatelessWidget {
  const RemoteNavigationBar({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.onHome,
    required this.onRecent,
  });

  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onRecent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconColor = enabled
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);
    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant,
                width: DesignTokens.spacingHairline,
              ),
            ),
          ),
          child: SizedBox(
            height: DesignTokens.componentPageHeaderHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _button(
                  tooltip: '返回',
                  enabled: enabled,
                  onPressed: onBack,
                  icon: Icons.arrow_back,
                  color: iconColor,
                ),
                _button(
                  tooltip: '主屏幕',
                  enabled: enabled,
                  onPressed: onHome,
                  icon: Icons.circle_outlined,
                  color: iconColor,
                ),
                _button(
                  tooltip: '最近任务',
                  enabled: enabled,
                  onPressed: onRecent,
                  icon: Icons.crop_square,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
  }) => SizedBox(
    width: 72,
    height: DesignTokens.componentPageHeaderHeight,
    child: IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      iconSize: DesignTokens.componentIconSize,
      icon: Icon(icon, color: color),
    ),
  );
}
