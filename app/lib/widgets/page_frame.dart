import 'dart:math' as math;

import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

class PageFrame extends StatefulWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.root = false,
    this.pane = false,
    this.titleContent,
    this.titleStyle,
    this.headerHeight = DesignTokens.componentPageHeaderHeight,
    this.actions,
    this.groupHorizontalActions = false,
    this.trailingAction,
    this.bottom,
    this.onBack,
    this.leading,
    this.backgroundColor,
  });
  final String title;
  final Widget child;
  final bool root;
  final bool pane;
  final Widget? titleContent;
  final TextStyle? titleStyle;
  final double headerHeight;
  final List<Widget>? actions;

  /// 仅为设计稿中的横向动作组共用表面。竖栏始终逐个摆放。
  final bool groupHorizontalActions;
  final Widget? trailingAction;

  /// Material is owned by the footer widget. PageFrame provides its layout.
  final Widget? bottom;
  final VoidCallback? onBack;
  final Widget? leading;
  final Color? backgroundColor;

  @override
  State<PageFrame> createState() => _PageFrameState();
}

class _PageFrameState extends State<PageFrame> {
  bool _scrolled = false;
  ScrollableState? _contentScrollable;
  ScrollPosition? get _contentPosition =>
      _contentScrollable?.mounted == true ? _contentScrollable!.position : null;
  Drag? _headerDrag;

  void _rememberPosition(BuildContext? context) {
    if (context != null) {
      _contentScrollable = Scrollable.maybeOf(context) ?? _contentScrollable;
    }
  }

  @override
  void dispose() {
    _headerDrag?.cancel();
    super.dispose();
  }

  int _headerLines(BuildContext context, BoxConstraints constraints) =>
      constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom < 400
      ? 1
      : 2;

  TextStyle? _titleStyle(BuildContext context, {bool measuring = false}) {
    if (widget.titleStyle case final style?) return style;
    final text = Theme.of(context).textTheme;
    final compact =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        400;
    return widget.root && !compact && (measuring || !_scrolled)
        ? text.displaySmall
        : text.titleLarge;
  }

  double _toolbarHeight(
    BuildContext context,
    BoxConstraints constraints, {
    bool includeActions = true,
  }) {
    final width =
        (constraints.maxWidth.clamp(
                  0,
                  DesignTokens.componentPageContentMaxWidth,
                ) -
                DesignTokens.componentIconButtonSize *
                    ((includeActions ? (widget.actions?.length ?? 0) : 0) +
                        (widget.trailingAction == null ? 0 : 1) +
                        2))
            .clamp(1.0, double.infinity);
    final painter = TextPainter(
      text: TextSpan(
        text: widget.title,
        style: _titleStyle(context, measuring: true),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _headerLines(context, constraints),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return (height + DesignTokens.spacingMd).clamp(
      widget.headerHeight,
      double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final router = GoRouter.maybeOf(context);
      final hasBack =
          widget.leading != null ||
          (widget.onBack != null ||
              !widget.root &&
                  !widget.pane &&
                  router != null &&
                  (router.canPop() ||
                      !['/devices', '/transfers', '/settings'].contains(
                        router.routeInformationProvider.value.uri.path,
                      )));
      final hasWindowChrome = DesktopWindowInsets.of(context) != null;
      final platformBar = liquid.GlassVerticalBar.maybeOf(context);
      final workspaceToolbar =
          widget.pane ||
          hasWindowChrome ||
          (platformBar == null &&
              windowEnvironmentOf(context).usesWorkspaceToolbar);
      final verticalBar = workspaceToolbar ? null : platformBar;
      final toolbarHeight = _toolbarHeight(
        context,
        constraints,
        includeActions: verticalBar == null,
      );
      final safe = MediaQuery.paddingOf(context);
      final extraTop = verticalBar == null
          ? 0.0
          : math.max(0.0, verticalBar.rowTop - safe.top);
      final extraSide = verticalBar == null
          ? 0.0
          : math.max(
              0.0,
              verticalBar.width -
                  (verticalBar.edge == liquid.GlassVerticalBarEdge.leading
                      ? safe.left
                      : safe.right) +
                  DesignTokens.spacingSm,
            );
      final top = workspaceToolbar ? 0.0 : safe.top + toolbarHeight + extraTop;
      final sideInsets = EdgeInsets.only(
        left: verticalBar?.edge == liquid.GlassVerticalBarEdge.leading
            ? safe.left + extraSide
            : 0,
        right: verticalBar?.edge == liquid.GlassVerticalBarEdge.trailing
            ? safe.right + extraSide
            : 0,
      );
      final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
      final onBack = widget.onBack ?? () => closePage<void>(context);
      final actions = widget.actions ?? const <Widget>[];
      final horizontalActions = actions.isEmpty
          ? null
          : widget.groupHorizontalActions && actions.length > 1
          ? GlassToolbarGroup(children: actions)
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignTokens.spacingXs,
              children: [
                for (final action in actions)
                  GlassToolbarGroup(children: [action]),
              ],
            );
      final actionMargin = widget.root && actions.isNotEmpty
          ? DesignTokens.spacingLg
          : DesignTokens.spacingMd;
      final appBar = AppBar(
        toolbarHeight: toolbarHeight,
        backgroundColor: DesignTokens.colorTransparent,
        surfaceTintColor: DesignTokens.colorTransparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        centerTitle: false,
        leadingWidth:
            DesignTokens.spacingMd + DesignTokens.componentIconButtonSize,
        titleSpacing: hasBack
            ? DesignTokens.spacingSm
            : widget.root
            ? DesignTokens.spacingLg
            : DesignTokens.spacingMd,
        leading: verticalBar != null || !hasBack
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DesignTokens.spacingMd,
                ),
                child: Center(
                  child:
                      widget.leading ??
                      Tooltip(
                        message: backLabel,
                        excludeFromSemantics: true,
                        child: GlassToolbarIconButton(
                          semanticLabel: backLabel,
                          onPressed: onBack,
                          icon: const Icon(AppIcons.back),
                        ),
                      ),
                ),
              ),
        title:
            widget.titleContent ??
            Text(
              widget.title,
              maxLines: _headerLines(context, constraints),
              overflow: TextOverflow.ellipsis,
              style: _titleStyle(context),
            ),
        actions: [
          if (verticalBar == null && horizontalActions != null)
            Padding(
              padding: EdgeInsets.only(
                right: widget.trailingAction == null
                    ? DesignTokens.spacingZero
                    : DesignTokens.spacingXs,
              ),
              child: Center(child: horizontalActions),
            ),
          if (widget.trailingAction != null)
            Center(child: widget.trailingAction!),
          if (widget.trailingAction != null ||
              (verticalBar == null && horizontalActions != null))
            SizedBox(width: actionMargin),
        ],
      );
      final scaffold = Scaffold(
        backgroundColor: widget.backgroundColor,
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: workspaceToolbar
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(toolbarHeight + extraTop),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                  onTap: () {},
                  onVerticalDragStart: (details) {
                    _headerDrag = _contentPosition?.drag(
                      details,
                      () => _headerDrag = null,
                    );
                  },
                  onVerticalDragUpdate: (details) =>
                      _headerDrag?.update(details),
                  onVerticalDragEnd: (details) => _headerDrag?.end(details),
                  onVerticalDragCancel: () => _headerDrag?.cancel(),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.componentPageContentMaxWidth,
                      ),
                      // The title plane is ordinary chrome. Only its
                      // independently interactive buttons own glass surfaces;
                      // a glass parent would clip their optical overshoot and
                      // turn the whole navigation strip into a frosted panel.
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: extraTop,
                          left:
                              verticalBar?.edge ==
                                  liquid.GlassVerticalBarEdge.leading
                              ? extraSide
                              : 0,
                          right:
                              verticalBar?.edge ==
                                  liquid.GlassVerticalBarEdge.trailing
                              ? extraSide
                              : 0,
                        ),
                        child: appBar,
                      ),
                    ),
                  ),
                ),
              ),
        body: Builder(
          builder: (context) => PageChromePadding(
            padding: EdgeInsets.only(
              top: top,
              bottom:
                  (MediaQuery.paddingOf(context).bottom -
                          (widget.bottom == null
                              ? 0
                              : MediaQuery.viewInsetsOf(context).bottom))
                      .clamp(0, double.infinity),
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              minimum: sideInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (workspaceToolbar)
                    _WorkspaceToolbar(
                      title: widget.title,
                      titleContent: widget.titleContent,
                      titleStyle: widget.titleStyle,
                      leading: widget.leading,
                      actions: horizontalActions,
                      actionMargin: actionMargin,
                      trailingAction: widget.trailingAction,
                      onBack: onBack,
                      hasBack: hasBack,
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: DesignTokens.componentPageContentMaxWidth,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NotificationListener<ScrollMetricsNotification>(
                              onNotification: (notification) {
                                _rememberPosition(notification.context);
                                return false;
                              },
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  _rememberPosition(notification.context);
                                  if (notification.metrics.axis ==
                                          Axis.vertical &&
                                      notification.depth <= 1) {
                                    final scrolled =
                                        notification.metrics.extentBefore >
                                        DesignTokens.spacingLg;
                                    if (_scrolled != scrolled) {
                                      setState(() => _scrolled = scrolled);
                                    }
                                  }
                                  return false;
                                },
                                child: widget.child,
                              ),
                            ),
                            if (_scrolled)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: PageChromeProtection(
                                  height: top,
                                  backgroundColor:
                                      widget.backgroundColor ??
                                      Theme.of(context).scaffoldBackgroundColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.bottom == null
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
                  minimum: sideInsets,
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.componentPageContentMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          DesignTokens.spacingMd,
                          DesignTokens.spacingXs,
                          DesignTokens.spacingMd,
                          DesignTokens.spacingMd,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: widget.bottom,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
      if (verticalBar == null) return scaffold;
      final verticalActions = <Widget>[
        if (widget.leading != null)
          widget.leading!
        else if (hasBack)
          GlassToolbarIconButton(
            semanticLabel: backLabel,
            onPressed: onBack,
            icon: const Icon(AppIcons.back),
          ),
        for (final action in actions) GlassToolbarGroup(children: [action]),
      ];
      if (verticalActions.isEmpty) return scaffold;
      return Stack(
        fit: StackFit.expand,
        children: [
          scaffold,
          GlassSideToolbar(bar: verticalBar, children: verticalActions),
        ],
      );
    },
  );
}

/// Carries page identity and actions within the workspace.
class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({
    required this.title,
    required this.titleContent,
    required this.titleStyle,
    required this.leading,
    required this.actions,
    required this.actionMargin,
    required this.trailingAction,
    required this.onBack,
    required this.hasBack,
  });

  final String title;
  final Widget? titleContent;
  final TextStyle? titleStyle;
  final Widget? leading;
  final Widget? actions;
  final double actionMargin;
  final Widget? trailingAction;
  final VoidCallback onBack;
  final bool hasBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    final window = DesktopWindowInsets.of(context);
    final rowPadding = window == null
        ? DesignTokens.spacingSm
        : (DesignTokens.componentPageHeaderHeight -
                  DesignTokens.componentIconButtonSize) /
              2;
    final trailing = <Widget>[?actions, ?trailingAction];
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: DesignTokens.componentPageContentMaxWidth,
        minHeight: DesignTokens.componentPageHeaderHeight,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          window == null
              ? DesignTokens.spacingMd
              : math.max(
                  DesignTokens.spacingMd,
                  window.left + DesignTokens.spacingXs,
                ),
          MediaQuery.paddingOf(context).top + rowPadding,
          window == null
              ? actionMargin
              : math.max(actionMargin, window.right + DesignTokens.spacingXs),
          rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null)
              leading!
            else if (hasBack)
              Tooltip(
                message: backLabel,
                excludeFromSemantics: true,
                child: GlassToolbarIconButton(
                  semanticLabel: backLabel,
                  onPressed: onBack,
                  icon: const Icon(AppIcons.back),
                ),
              ),
            if (leading != null || hasBack)
              const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: DesktopWindowDragArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: window == null
                        ? 0
                        : DesignTokens.componentIconButtonSize,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    heightFactor: 1,
                    child:
                        titleContent ??
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle ?? theme.textTheme.headlineSmall,
                        ),
                  ),
                ),
              ),
            ),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: DesignTokens.spacingMd),
              ...trailing,
            ],
          ],
        ),
      ),
    );
  }
}
