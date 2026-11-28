import 'dart:math' as math;

import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

typedef PageSearch = ({TextEditingController controller, String hint});

/// 页头（Ardot 页头 37:795）：安全区下高 72，背景透明，身后是顶部渐隐。
///
/// - 根页：`page-title` 标题起始距边 16，尾部玻璃按钮或按钮组距边 8。
/// - 子页：起始为 44 点玻璃返回键，距边 8；`title3` 标题紧跟其后，间距 8。
/// - 选择：起始为关闭（[leading]），所选数量居中，尾部为全选或取消全选。

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
    this.headerHeight = DesignTokens.componentPageBarHeight,
    this.actions,
    this.groupHorizontalActions = true,
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

  /// 页头相邻的两个及以上图标按钮（含搜索）合成一个玻璃胶囊（design.md「按钮」）。
  /// 为假时逐个摆放。竖栏始终逐个摆放。
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

  TextStyle _titleStyle(BuildContext context) {
    if (widget.titleStyle case final style?) return style;
    final type = AppTypography.of(context);
    final compact =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        400;
    return widget.root && !compact ? type.pageTitle : type.title3;
  }

  double _toolbarHeight(
    BuildContext context,
    BoxConstraints constraints, {
    bool includeActions = true,
  }) {
    final width =
        (constraints.maxWidth.clamp(0, DesignTokens.componentPageMaxWidth) -
                DesignTokens.componentBarButtonSize *
                    ((includeActions ? (widget.actions?.length ?? 0) : 0) +
                        (widget.trailingAction == null ? 0 : 1) +
                        2))
            .clamp(1.0, double.infinity);
    final painter = TextPainter(
      text: TextSpan(text: widget.title, style: _titleStyle(context)),
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
      final bodyStyle = AppTypography.of(context).body;
      final searchHeight = math.max(
        DesignTokens.componentSearchFieldHeight,
        MediaQuery.textScalerOf(context).scale(bodyStyle.fontSize!) *
                (bodyStyle.height ?? 1) +
            2 * DesignTokens.spacingMd,
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
      final groupSearch =
          widget.groupHorizontalActions &&
          actions.isNotEmpty &&
          verticalBar == null;
      final searchButton = search == null || searching
          ? null
          : groupSearch
          ? GlassActionIcon(
              key: const ValueKey('page-search-open'),
              focusNode: _searchButtonFocus,
              tooltip: search.hint,
              onPressed: _openSearch,
              icon: const Icon(AppIcons.search),
            )
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
        if (groupSearch)
          GlassToolbarGroup(children: [?searchButton, ...actions])
        else ...[
          ?searchButton,
          if (widget.groupHorizontalActions && actions.length > 1)
            GlassToolbarGroup(children: actions)
          else
            for (final action in actions) GlassToolbarGroup(children: [action]),
        ],
      ];
      final horizontalActions = actionGroups.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignTokens.componentPageBarGap,
              children: actionGroups,
            );
      // 尾部按钮距边 8（Ardot 页头 37:784/37:787 右内距）。
      const actionMargin = DesignTokens.spacingSm;
      final clear = AppColors.of(context).page.withAlpha(0);
      final selection = widget.leading != null && !searching;
      final appBar = AppBar(
        toolbarHeight: toolbarHeight,
        backgroundColor: clear,
        surfaceTintColor: clear,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        centerTitle: selection,
        leadingWidth:
            DesignTokens.spacingSm + DesignTokens.componentBarButtonSize,
        titleSpacing: hasBack && !searching
            ? DesignTokens.spacingSm
            : DesignTokens.spacingLg,
        leading: searching || verticalBar != null || !hasBack
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DesignTokens.spacingSm,
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
                    ? 0
                    : DesignTokens.componentPageBarGap,
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
                        maxWidth: DesignTokens.componentPageMaxWidth,
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
                      titleStyle: _titleStyle(context),
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
                          maxWidth: DesignTokens.componentPageMaxWidth,
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
                                          position == _contentPosition)) {}
                                  return false;
                                },
                                child: widget.child,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: PageChromeProtection(
                                height: top,
                                backgroundColor:
                                    widget.backgroundColor ??
                                    AppColors.of(context).page,
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
                        maxWidth: DesignTokens.componentPageMaxWidth,
                      ),
                      child: Padding(
                        // 底部固定动作左右 16，底边留出安全区和 8。
                        padding: const EdgeInsets.fromLTRB(
                          DesignTokens.spacingLg,
                          DesignTokens.spacingSm,
                          DesignTokens.spacingLg,
                          DesignTokens.spacingSm,
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final focusColor = colors.primary;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(height / 2),
      borderSide: BorderSide.none,
    );
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
          ? Row(
              key: fieldKey,
              spacing: DesignTokens.spacingSm,
              children: [
                Expanded(
                  child: TextField(
                    controller: search.controller,
                    focusNode: focus,
                    style: type.body,
                    textInputAction: TextInputAction.search,
                    cursorColor: focusColor,
                    decoration: InputDecoration(
                      hintText: search.hint,
                      hintStyle: type.body.copyWith(
                        color: colors.textSecondary,
                      ),
                      isDense: true,
                      constraints: BoxConstraints(minHeight: height),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingXs,
                        vertical: DesignTokens.spacingXs,
                      ),
                      filled: true,
                      fillColor: colors.inset,
                      border: fieldBorder,
                      focusedBorder: fieldBorder.copyWith(
                        borderSide: BorderSide(
                          color: focusColor,
                          width: DesignTokens.componentControlFocusSize,
                        ),
                      ),
                      // 搜索框 `search-field`：起始 20 点搜索图形，尾部清除按钮。
                      prefixIcon: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: DesignTokens.componentSearchFieldPadding,
                          end: DesignTokens.spacingSm,
                        ),
                        child: Icon(
                          AppIcons.search,
                          size: DesignTokens.componentSectionGlyphSize,
                          color: colors.textSecondary,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(),
                      suffixIcon: ValueListenableBuilder(
                        valueListenable: search.controller,
                        builder: (context, value, _) => value.text.isEmpty
                            ? const SizedBox.shrink()
                            : GlassActionIcon(
                                icon: const Icon(AppIcons.close),
                                tooltip: '清除搜索',
                                color: colors.textSecondary,
                                iconSize:
                                    DesignTokens.componentSectionGlyphSize,
                                onPressed: search.controller.clear,
                              ),
                      ),
                      suffixIconConstraints: const BoxConstraints(),
                    ),
                  ),
                ),
                Tooltip(
                  message: '关闭搜索',
                  excludeFromSemantics: true,
                  child: GlassToolbarIconButton(
                    icon: const Icon(AppIcons.close),
                    semanticLabel: '关闭搜索',
                    onPressed: onClose,
                  ),
                ),
              ],
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
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    final window = DesktopWindowInsets.of(context);
    final trailing = <Widget>[?actions, ?trailingAction];
    final heading = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.componentBarButtonSize,
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
              style: titleStyle,
            ),
      ),
    );
    final leadingSlot = leading != null || hasBack;
    // 页头行高 72，位于安全区或桌面沉浸标题栏之下；起始距边根页 16、有返回时 8。
    return Padding(
      padding: EdgeInsets.fromLTRB(
        leadingSlot ? DesignTokens.spacingSm : DesignTokens.spacingLg,
        math.max(MediaQuery.paddingOf(context).top, window?.top ?? 0),
        actionMargin,
        0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignTokens.componentPageMaxWidth,
          minHeight: DesignTokens.componentPageBarHeight,
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
            if (leadingSlot) const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: DesktopWindowDragArea(
                enabled: draggableTitle,
                child: heading,
              ),
            ),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: DesignTokens.spacingSm),
              ...trailing,
            ],
          ],
        ),
      ),
    );
  }
}
