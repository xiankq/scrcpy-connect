import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_controls_protection.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class MediaPreviewToolbar extends StatelessWidget {
  const MediaPreviewToolbar({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return MediaControlsProtection(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            children: [
              Tooltip(
                message: MaterialLocalizations.of(context).backButtonTooltip,
                child: GlassToolbarIconButton(
                  semanticLabel: MaterialLocalizations.of(context)
                      .backButtonTooltip,
                  variant: GlassVariant.clear,
                  interactionScale: GlassMaterial.reduceMotion(context)
                      ? 1
                      : DesignTokens.componentGlassInteractionScale,
                  anchorStretch: !GlassMaterial.reduceMotion(context),
                  onPressed: onBack,
                  icon: const Icon(
                    LucideIcons.chevronLeft,
                    color: DesignTokens.colorWhite,
                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}
