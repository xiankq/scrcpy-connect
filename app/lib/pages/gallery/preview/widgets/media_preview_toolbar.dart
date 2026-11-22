import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_controls_protection.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
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
    final window = DesktopWindowInsets.of(context);
    final verticalPadding = window == null
        ? DesignTokens.spacingMd
        : (DesignTokens.componentPageHeaderHeight -
                  DesignTokens.componentIconButtonSize) /
              2;
    return MediaControlsProtection(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            window != null && window.left > 0
                ? window.left
                : DesignTokens.spacingMd,
            verticalPadding,
            window != null && window.right > 0
                ? window.right
                : DesignTokens.spacingMd,
            verticalPadding,
          ),
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
                child: DesktopWindowDragArea(
                  child: SizedBox(
                    height: DesignTokens.componentIconButtonSize,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
