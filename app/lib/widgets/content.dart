import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

class ContentLoadingIndicator extends HookWidget {
  const ContentLoadingIndicator({
    super.key,
    this.size = DesignTokens.componentIconSize,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.reduceMotionOf(context);
    final rotation = useAnimationController(
      duration: const Duration(milliseconds: 900),
    );
    useEffect(() {
      if (animate) {
        rotation.repeat();
      } else {
        rotation.reset();
      }
      return null;
    }, [rotation, animate]);
    return Semantics(
      label: '正在加载',
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: RotationTransition(
          turns: rotation,
          child: Icon(
            LucideIcons.loaderCircle,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            size: size,
          ),
        ),
      ),
    );
  }
}

class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.spacingMd),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(
      DesignTokens.componentContentPanelRounded,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class FeatureIcon extends StatelessWidget {
  const FeatureIcon(
    this.icon, {
    super.key,
    this.color = ConnectTokens.primary,
    this.size = DesignTokens.componentFeatureIconSize,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final resolved = ConnectTokens.accent(context, color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolved.withValues(
          alpha: DesignTokens.componentFeatureIconOpacity,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
      ),
      child: Icon(
        icon,
        color: resolved,
        size: DesignTokens.componentIconFeatureSize,
      ),
    );
  }
}

class EmptyContent extends StatelessWidget {
  const EmptyContent({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentEmptyContentPadding,
          vertical: DesignTokens.componentEmptyContentVerticalPadding,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.componentEmptyContentWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeatureIcon(
                icon,
                size: DesignTokens.componentEmptyContentIconSize,
              ),
              const SizedBox(height: DesignTokens.componentEmptyContentGap),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(
                  height: DesignTokens.componentEmptyContentMessageGapHeight,
                ),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: DesignTokens.componentEmptyContentGap),
                action!,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
