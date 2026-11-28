import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/pages/gallery/preview/widgets/media_controls_protection.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
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
    final side = liquid.GlassVerticalBar.maybeOf(context);
    final atLeft = side?.edge == liquid.GlassVerticalBarEdge.leading;
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    final back = Tooltip(
      message: backLabel,
      excludeFromSemantics: true,
      child: GlassToolbarIconButton(
        semanticLabel: backLabel,
        variant: GlassVariant.clear,
        onPressed: onBack,
        icon: const Icon(AppIcons.back),
      ),
    );
    // 与页头一致：高 72，44 点返回键距起始边 8，标题紧随其后间距 8（Ardot 页头 37:795）。
    const verticalPadding =
        (DesignTokens.componentPageBarHeight -
            DesignTokens.componentBarButtonSize) /
        2;
    final header = MediaControlsProtection(
      child: SafeArea(
        bottom: false,
        minimum: EdgeInsets.only(
          left: atLeft ? side!.width : 0,
          right: side != null && !atLeft ? side.width : 0,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            window != null && window.left > 0
                ? window.left + DesignTokens.spacingXs
                : DesignTokens.spacingSm,
            verticalPadding,
            window != null && window.right > 0
                ? window.right + DesignTokens.spacingXs
                : DesignTokens.componentPagePadding,
            verticalPadding,
          ),
          child: Row(
            children: [
              if (side == null) ...[
                back,
                const SizedBox(width: DesignTokens.spacingSm),
              ],
              Expanded(
                child: DesktopWindowDragArea(
                  child: SizedBox(
                    height: DesignTokens.componentBarButtonSize,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.of(context).title3
                            .copyWith(color: DesignTokens.colorOnMedia),
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
    if (side == null) return header;
    return Stack(
      children: [
        Align(alignment: Alignment.topCenter, child: header),
        GlassSideToolbar(
          bar: side,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -DesignTokens.spacingSm,
                  right: -DesignTokens.spacingSm,
                  top: -DesignTokens.spacingSm,
                  bottom: -DesignTokens.spacingSm,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            DesignTokens
                                .componentMediaProtectionBackgroundColor,
                            DesignTokens.componentMediaProtectionBackgroundColor
                                .withAlpha(0),
                          ],
                          stops: [0.15, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                back,
              ],
            ),
          ],
        ),
      ],
    );
  }
}
