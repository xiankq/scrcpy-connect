import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

/// 边距归滚动内容所有，使视口可以延伸到界面装饰下方。
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

/// 用于自定义页面滚动视图的首个 sliver，不用于模态路由。
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

/// 不滚动的加载和错误状态留在页面可用区域内。
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

/// 滚动边缘保护完全位于标题区域内。
class PageChromeProtection extends StatelessWidget {
  const PageChromeProtection({
    super.key,
    required this.height,
    required this.backgroundColor,
  });
  final double height;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final extent = height;
    final protected = backgroundColor.withValues(
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
              stops: [
                0,
                ((height - DesignTokens.spacingLg) / extent).clamp(0, 1),
                1,
              ],
              colors: [
                protected,
                protected,
                backgroundColor.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
