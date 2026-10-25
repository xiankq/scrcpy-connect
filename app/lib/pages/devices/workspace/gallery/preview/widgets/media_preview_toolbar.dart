import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'media_controls_protection.dart';

class MediaPreviewToolbar extends StatelessWidget {
  const MediaPreviewToolbar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onSave,
    required this.onShare,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return MediaControlsProtection(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: GlassSurfaceGroup(
            variant: GlassVariant.clear,
            child: Row(
              children: [
                GlassTooltip(
                  message: MaterialLocalizations.of(context).backButtonTooltip,
                  child: GlassIconButton(
                    semanticLabel: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    size: DesignTokens.componentIconButtonSize,
                    iconSize: DesignTokens.componentIconSize,
                    settings: GlassMaterial.settings(
                      context,
                      variant: GlassVariant.clear,
                    ),
                    quality: GlassMaterial.quality(context),
                    interactionScale: GlassMaterial.reduceMotion(context)
                        ? 1
                        : DesignTokens.componentGlassInteractionScale,
                    anchorStretch: !GlassMaterial.reduceMotion(context),
                    onPressed: onBack,
                    icon: const Icon(LucideIcons.chevronLeft),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingXs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingXs),
                GlassToolbarGroup(
                  variant: GlassVariant.clear,
                  children: [
                    GlassActionIcon(
                      tooltip: '保存原文件',
                      color: Theme.of(context).colorScheme.onSurface,
                      onPressed: onSave,
                      icon: const Icon(LucideIcons.download),
                    ),
                    GlassActionIcon(
                      tooltip: '系统分享',
                      color: Theme.of(context).colorScheme.onSurface,
                      onPressed: onShare,
                      icon: const Icon(LucideIcons.share2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
