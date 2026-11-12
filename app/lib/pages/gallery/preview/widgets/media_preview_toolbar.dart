import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_controls_protection.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

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
                    if (supportsSystemFileShare)
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
