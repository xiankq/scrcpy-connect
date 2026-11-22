import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:foldable/foldable.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

/// Lists and details share the same mounted panes across window changes.
final class WorkspacePanes extends StatelessWidget {
  const WorkspacePanes({
    super.key,
    required this.builder,
    this.onCloseDetail,
    this.hasContent = true,
  });

  final ({Widget list, Widget detail}) Function(BuildContext, bool) builder;
  final VoidCallback? onCloseDetail;
  final bool hasContent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final window = windowEnvironmentOf(context);
      final fold = DuoMediaQuery.maybeOf(context);
      final verticalBar = liquid.GlassVerticalBar.maybeOf(context);
      final width = constraints.maxWidth;
      final left = verticalBar?.edge == liquid.GlassVerticalBarEdge.leading
          ? verticalBar!.width + DesignTokens.spacingSm
          : window.insets.left;
      final right = verticalBar?.edge == liquid.GlassVerticalBarEdge.trailing
          ? verticalBar!.width + DesignTokens.spacingSm
          : window.insets.right;
      final divider = window.verticalPaneDivider;
      final available = (width - left - right).clamp(0.0, width);
      final duo =
          fold?.isFoldable == true &&
          fold?.horizontalSizeClass == SizeClass.regular &&
          (constraints.maxWidth > constraints.maxHeight || divider != null);
      final minimum = duo
          ? DesignTokens.componentWorkspaceDuoPaneWidth
          : DesignTokens.componentWorkspacePaneWidth;
      final gap = DesignTokens.spacingSm;
      final hasDivider = divider != null && (width - window.width).abs() < 1;
      final dividerOffset = hasDivider ? divider.left - left : null;
      final dividerWidth = hasDivider ? divider.width : gap;
      final split =
          hasContent &&
          (duo ||
              window.width - window.insets.left - window.insets.right >=
                  DesignTokens.componentWorkspaceSplitWidth) &&
          available >= minimum * 2 + dividerWidth &&
          (dividerOffset == null ||
              dividerOffset >= minimum &&
                  available - dividerOffset - dividerWidth >= minimum);
      final singleWidth = hasDivider
          ? width - divider.left - divider.width
          : width;
      final listWidth = split
          ? dividerOffset ?? (duo ? (available - gap) / 2 : minimum)
          : singleWidth;
      final detailWidth = split
          ? available - listWidth - dividerWidth
          : singleWidth;
      final panes = builder(context, split);

      // MediaQuery still describes the host view. The lateral bar/padding is
      // already reserved by this split, so each PageFrame receives pane insets.
      final media = MediaQuery.of(context);
      final paneMedia = split
          ? media.removePadding(removeLeft: true, removeRight: true)
          : media;
      final desktop = DesktopWindowInsets.of(context);
      Widget inPane(Widget child, {required bool detail}) => MediaQuery(
        data: paneMedia,
        child: split && desktop != null
            ? DesktopWindowInsets(
                left: detail ? 0 : desktop.left,
                right: detail ? desktop.right : 0,
                top: desktop.top,
                child: child,
              )
            : child,
      );

      final closeDetail = split ? null : onCloseDetail;
      final showDetail = closeDetail != null;
      final layout = Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: split ? left : width - singleWidth,
            width: listWidth,
            child: ExcludeFocus(
              excluding: showDetail && !split,
              child: Offstage(
                offstage: showDetail && !split,
                child: inPane(panes.list, detail: false),
              ),
            ),
          ),
          if (split && !hasDivider)
            Positioned(
              top: DesignTokens.spacingMd,
              bottom: DesignTokens.spacingMd,
              left: left + listWidth + gap / 2,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.outlineVariant,
                child: const SizedBox(width: DesignTokens.spacingHairline),
              ),
            ),
          Positioned(
            top: 0,
            bottom: 0,
            right: split ? right : 0,
            width: detailWidth,
            child: ExcludeFocus(
              excluding: !showDetail && !split,
              child: Offstage(
                offstage: !showDetail && !split,
                child: inPane(panes.detail, detail: true),
              ),
            ),
          ),
        ],
      );
      return PopScope(
        canPop: !showDetail,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) closeDetail?.call();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): ?closeDetail,
          },
          child: layout,
        ),
      );
    },
  );
}
