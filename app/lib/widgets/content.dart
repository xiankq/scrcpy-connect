import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../styles/generated/design_tokens.g.dart';
import '../styles/theme.dart';

class ContentLoadingIndicator extends StatelessWidget {
  const ContentLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: CupertinoActivityIndicator(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        animating: !MediaQuery.disableAnimationsOf(context),
      ),
    ),
  );
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
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
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
              const SizedBox(
                height: DesignTokens.componentEmptyContentMessageGapHeight,
              ),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
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
