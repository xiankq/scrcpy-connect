import 'dart:math' as math;

import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

typedef PageSearch = ({TextEditingController controller, String hint});

class PageFrame extends StatefulWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.root = false,
    this.pane = false,
    this.titleContent,
    this.search,
    this.primaryScrollController,
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
  final PageSearch? search;
  final ScrollController? primaryScrollController;
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
  bool _searchOpen = false;
  final _searchFocus = FocusNode(debugLabel: '页头搜索');
  final _searchButtonFocus = FocusNode(debugLabel: '打开搜索');
  ScrollableState? _contentScrollable;
  ScrollPosition? get _contentPosition {
    final controller = widget.primaryScrollController;
    if (controller != null) {
      return controller.hasClients ? controller.position : null;
    }
    return _contentScrollable?.mounted == true
        ? _contentScrollable!.position
        : null;
  }

  Drag? _headerDrag;

  @override
  void didUpdateWidget(PageFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryScrollController != widget.primaryScrollController) {
      _headerDrag?.cancel();
      final position = _contentPosition;
      _scrolled =
          position != null &&
          position.hasContentDimensions &&
          position.extentBefore > DesignTokens.spacingLg;
    }
  }

  ScrollPosition? _rememberPosition(BuildContext? context) {
    final scrollable = context == null ? null : Scrollable.maybeOf(context);
    _contentScrollable = scrollable ?? _contentScrollable;
    return scrollable?.position;
  }

  @override
  void dispose() {
    _headerDrag?.cancel();
    _searchFocus.dispose();
    _searchButtonFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (widget.search == null || _searchOpen) return;
    setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    widget.search?.controller.clear();
    setState(() => _searchOpen = false);
    _searchButtonFocus.requestFocus();
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
      final search = widget.search;
      final searching = search != null && _searchOpen;
      final bodyStyle = Theme.of(context).textTheme.bodyMedium!;
      final searchHeight = math.max(
        DesignTokens.componentIconButtonSize,
        MediaQuery.textScalerOf(context).scale(bodyStyle.fontSize!) *
                (bodyStyle.height ?? 1) +
            2 * DesignTokens.spacingSm,
      );
      final toolbarHeight = math.max(
        _toolbarHeight(
          context,
          constraints,
          includeActions: verticalBar == null,
        ),
        search == null ? 0.0 : searchHeight + DesignTokens.spacingXs,
      );
      final titleStyle = _titleStyle(context);
      final headerTitle =
          widget.titleContent ??
          Text(
            widget.title,
            maxLines: _headerLines(context, constraints),
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          );
      final title = search == null
          ? null
          : _SearchTitle(
              searching: searching,
              title: headerTitle,
              search: search,
              focus: _searchFocus,
              onClose: _closeSearch,
              height: searchHeight,
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
      final actions = searching
          ? const <Widget>[]
          : widget.actions ?? const <Widget>[];
      final searchButton = search == null || searching
          ? null
          : Tooltip(
              message: search.hint,
              excludeFromSemantics: true,
              child: GlassToolbarIconButton(
                key: const ValueKey('page-search-open'),
                focusNode: _searchButtonFocus,
                semanticLabel: search.hint,
                onPressed: _openSearch,
                icon: const Icon(AppIcons.search),
              ),
            );
      final trailingAction = searching ? null : widget.trailingAction;
      final actionGroups = [
        ?searchButton,
        if (widget.groupHorizontalActions && actions.length > 1)
          GlassToolbarGroup(children: actions)
        else
          for (final action in actions) GlassToolbarGroup(children: [action]),
      ];
      final horizontalActions = actionGroups.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignTokens.spacingXs,
              children: actionGroups,
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
        titleSpacing: searching
            ? DesignTokens.spacingMd
            : hasBack
            ? DesignTokens.spacingSm
            : widget.root
            ? DesignTokens.spacingLg
            : DesignTokens.spacingMd,
        leading: searching || verticalBar != null || !hasBack
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
        title: title ?? headerTitle,
        actions: [
          if (verticalBar == null && horizontalActions != null)
            Padding(
              padding: EdgeInsets.only(
                right: trailingAction == null
                    ? DesignTokens.spacingZero
                    : DesignTokens.spacingXs,
              ),
              child: Center(child: horizontalActions),
            ),
          if (trailingAction != null) Center(child: trailingAction),
          if (trailingAction != null ||
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
                      titleContent: title ?? widget.titleContent,
                      titleStyle: widget.titleStyle,
                      leading: searching ? null : widget.leading,
                      actions: horizontalActions,
                      actionMargin: actionMargin,
                      trailingAction: trailingAction,
                      onBack: onBack,
                      hasBack: hasBack && !searching,
                      draggableTitle: !searching,
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
                                  final position = _rememberPosition(
                                    notification.context,
                                  );
                                  if (notification.metrics.axis ==
                                          Axis.vertical &&
                                      notification.depth <= 1 &&
                                      (widget.primaryScrollController == null ||
                                          position == _contentPosition)) {
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
      final verticalActions = <Widget>[
        if (!searching && widget.leading != null)
          widget.leading!
        else if (!searching && hasBack)
          GlassToolbarIconButton(
            semanticLabel: backLabel,
            onPressed: onBack,
            icon: const Icon(AppIcons.back),
          ),
        ?searchButton,
        for (final action in actions) GlassToolbarGroup(children: [action]),
      ];
      final page = verticalBar == null || verticalActions.isEmpty
          ? scaffold
          : Stack(
              fit: StackFit.expand,
              children: [
                scaffold,
                GlassSideToolbar(bar: verticalBar, children: verticalActions),
              ],
            );
      if (search == null) return page;
      return PopScope(
        canPop: !searching,
        onPopInvokedWithResult: (popped, _) {
          if (!popped && searching) _closeSearch();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _openSearch,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openSearch,
            if (searching)
              const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
          },
          child: Focus(autofocus: true, child: page),
        ),
      );
    },
  );
}

class _SearchTitle extends StatelessWidget {
  const _SearchTitle({
    required this.searching,
    required this.title,
    required this.search,
    required this.focus,
    required this.onClose,
    required this.height,
  });

  final bool searching;
  final Widget title;
  final PageSearch search;
  final FocusNode focus;
  final VoidCallback onClose;
  final double height;

  @override
  Widget build(BuildContext context) {
    const fieldKey = ValueKey('page-search-field');
    final reduced = GlassMaterial.reduceMotion(context);
    final scheme = Theme.of(context).colorScheme;
    final solid = opaqueGlass(context);
    final alignment = AlignmentDirectional.centerStart.resolve(
      Directionality.of(context),
    );
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : panelOpenDuration,
      reverseDuration: reduced ? Duration.zero : panelCloseDuration,
      switchInCurve: panelCurve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [
          for (final child in previous)
            Positioned.fill(
              child: Align(
                alignment: alignment,
                child: IgnorePointer(
                  child: ExcludeFocus(child: ExcludeSemantics(child: child)),
                ),
              ),
            ),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (child.key != fieldKey || reduced) return fade;
        return AnimatedBuilder(
          animation: animation,
          child: fade,
          builder: (context, child) => ClipRect(
            clipBehavior: animation.isCompleted ? Clip.none : Clip.hardEdge,
            child: Align(
              alignment: alignment,
              widthFactor: .82 + .18 * animation.value,
              child: child,
            ),
          ),
        );
      },
      child: searching
          ? liquid.GlassSearchBar(
              key: fieldKey,
              controller: search.controller,
              focusNode: focus,
              height: height,
              placeholder: search.hint,
              onCancel: onClose,
              showsCancelButton: true,
              cancelButtonAlwaysVisible: true,
              clearButtonSemanticLabel: '清除搜索',
              cancelButtonSemanticLabel: '关闭搜索',
              textStyle: Theme.of(context).textTheme.bodyMedium,
              placeholderStyle: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              useOwnLayer: true,
              quality: solid ? null : GlassMaterial.quality(context),
              surfaceStyle: solid ? liquid.GlassSurfaceStyle.solid : null,
              color: solid ? scheme.surface : null,
            )
          : KeyedSubtree(key: const ValueKey('page-heading'), child: title),
    );
  }
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
    required this.draggableTitle,
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
  final bool draggableTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    final window = DesktopWindowInsets.of(context);
    final rowPadding = window == null
        ? DesignTokens.spacingSm
        : DesignTokens.componentDesktopHeaderPadding;
    final trailing = <Widget>[?actions, ?trailingAction];
    final heading = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: window == null ? 0 : DesignTokens.componentIconButtonSize,
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
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: DesignTokens.componentPageContentMaxWidth,
        minHeight: DesignTokens.componentPageHeaderHeight,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          math.max(MediaQuery.paddingOf(context).top, window?.top ?? 0) +
              rowPadding,
          actionMargin,
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
                enabled: draggableTitle,
                child: heading,
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
