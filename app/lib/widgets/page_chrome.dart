import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

/// Insets belong to scroll content so its viewport can extend behind chrome.
class PageChromePadding extends InheritedWidget {
  const PageChromePadding({
    super.key,
    required this.padding,
    this.showRecovery = true,
    required super.child,
  });
  final EdgeInsets padding;
  final bool showRecovery;

  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PageChromePadding>()
          ?.padding ??
      EdgeInsets.zero;

  static bool hasRecovery(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PageChromePadding>()
          ?.showRecovery ??
      false;

  static Widget removeTop({
    required BuildContext context,
    required Widget child,
  }) => PageChromePadding(
    padding: of(context).copyWith(top: 0),
    showRecovery: false,
    child: child,
  );

  @override
  bool updateShouldNotify(PageChromePadding oldWidget) =>
      padding != oldWidget.padding || showRecovery != oldWidget.showRecovery;
}

/// The leading sliver used by custom page scroll views, never modal routes.
class PageChromeSliver extends StatelessWidget {
  const PageChromeSliver({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: PageChromePadding.of(context).top),
        if (PageChromePadding.hasRecovery(context))
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height / 2,
            ),
            child: const RecoveryStatus(),
          ),
      ],
    ),
  );
}

class PageChromeBottomSliver extends StatelessWidget {
  const PageChromeBottomSliver({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: PageChromePadding.of(context).bottom),
  );
}

/// Non-scrolling loading and error states stay inside the usable page area.
class PageChromeBody extends StatelessWidget {
  const PageChromeBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: PageChromePadding.of(context),
    child: PageChromePadding.hasRecovery(context)
        ? LayoutBuilder(
            builder: (context, constraints) => !constraints.hasBoundedHeight
                ? child
                : Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight / 2,
                        ),
                        child: const RecoveryStatus(),
                      ),
                      Expanded(child: child),
                    ],
                  ),
          )
        : child,
  );
}

/// Protects the full title area, then fades into the scrolling content.
class PageChromeProtection extends StatelessWidget {
  const PageChromeProtection({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    final extent = height + DesignTokens.spacingLg;
    final protected = canvas.withValues(
      alpha: DesignTokens.componentScrollEdgeOpacity,
    );
    return IgnorePointer(
      child: SizedBox(
        height: extent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, height / extent, 1],
              colors: [protected, protected, canvas.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
