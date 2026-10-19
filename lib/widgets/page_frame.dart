import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.trailingAction,
    this.bottom,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? trailingAction;
  final Widget? bottom;
  int _headerLines(BuildContext context, BoxConstraints constraints) =>
      constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom < 400
      ? 1
      : 2;

  double _toolbarHeight(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context).textTheme;
    final width =
        (constraints.maxWidth -
                DesignTokens.componentIconButtonSize *
                    ((actions?.length ?? 0) +
                        (trailingAction == null ? 0 : 1) +
                        2))
            .clamp(1.0, double.infinity);
    double height(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: _headerLines(context, constraints),
      )..layout(maxWidth: width);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final content = height(title, theme.titleLarge);
    return (content + DesignTokens.spacingMd).clamp(
      DesignTokens.componentPageHeaderHeight,
      double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final hasBack =
          GoRouter.maybeOf(context) != null &&
          (GoRouter.of(context).canPop() ||
              !['/devices', '/transfers', '/settings'].contains(
                GoRouter.of(context).routeInformationProvider.value.uri.path,
              ));
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: _toolbarHeight(context, constraints),
          automaticallyImplyLeading: false,
          leadingWidth:
              DesignTokens.spacingMd + DesignTokens.componentIconButtonSize,
          titleSpacing: hasBack
              ? DesignTokens.spacingSm
              : DesignTokens.spacingMd,
          leading: hasBack
              ? Padding(
                  padding: const EdgeInsets.only(left: DesignTokens.spacingMd),
                  child: Center(
                    child: SizedBox.square(
                      dimension: DesignTokens.componentIconButtonSize,
                      child: Glass(
                        radius: DesignTokens.roundedFull,
                        child: BackButton(
                          onPressed: () => closePage<void>(context),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
          title: Text(
            title,
            maxLines: _headerLines(context, constraints),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          actions:
              (actions == null || actions!.isEmpty) && trailingAction == null
              ? null
              : [
                  if (actions != null && actions!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        right: trailingAction == null
                            ? DesignTokens.spacingZero
                            : DesignTokens.spacingXs,
                      ),
                      child: Center(
                        child: GlassToolbarGroup(children: actions!),
                      ),
                    ),
                  if (trailingAction != null) Center(child: trailingAction!),
                  const SizedBox(width: DesignTokens.spacingMd),
                ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
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
          ),
        ),
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingXs,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
                  child: bottom,
                ),
              ),
      );
    },
  );
}
