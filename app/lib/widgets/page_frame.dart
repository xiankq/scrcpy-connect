import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

class PageFrame extends StatefulWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.root = false,
    this.titleContent,
    this.actions,
    this.trailingAction,
    this.bottom,
    this.bottomRadius = DesignTokens.roundedLg,
    this.onBack,
    this.leading,
    this.backgroundColor,
  });
  final String title;
  final Widget child;
  final bool root;
  final Widget? titleContent;
  final List<Widget>? actions;
  final Widget? trailingAction;
  final Widget? bottom;
  final double bottomRadius;
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
    final text = Theme.of(context).textTheme;
    final compact =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        400;
    return widget.root && !compact && (measuring || !_scrolled)
        ? text.displaySmall
        : text.titleLarge;
  }

  double _toolbarHeight(BuildContext context, BoxConstraints constraints) {
    final width =
        (constraints.maxWidth.clamp(
                  0,
                  DesignTokens.componentPageContentMaxWidth,
                ) -
                DesignTokens.componentIconButtonSize *
                    ((widget.actions?.length ?? 0) +
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
      DesignTokens.componentPageHeaderHeight,
      double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final router = GoRouter.maybeOf(context);
      final hasBack =
          widget.leading != null ||
          !widget.root &&
              router != null &&
              (router.canPop() ||
                  ![
                    '/devices',
                    '/transfers',
                    '/settings',
                  ].contains(router.routeInformationProvider.value.uri.path));
      final toolbarHeight = _toolbarHeight(context, constraints);
      final top = MediaQuery.paddingOf(context).top + toolbarHeight;
      final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
      final onBack = widget.onBack ?? () => closePage<void>(context);
      final reduceMotion = GlassMaterial.reduceMotion(context);
      final appBar = AppBar(
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        leadingWidth:
            DesignTokens.spacingMd + DesignTokens.componentIconButtonSize,
        titleSpacing: hasBack ? DesignTokens.spacingSm : DesignTokens.spacingMd,
        leading:
            widget.leading ??
            (hasBack
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: DesignTokens.spacingMd,
                    ),
                    child: Center(
                      child: GlassTooltip(
                        message: backLabel,
                        child: GlassIconButton(
                          semanticLabel: backLabel,
                          size: DesignTokens.componentIconButtonSize,
                          iconSize: DesignTokens.componentIconSize,
                          settings: GlassMaterial.settings(context),
                          quality: GlassMaterial.quality(context),
                          interactionScale: reduceMotion
                              ? 1
                              : DesignTokens.componentGlassInteractionScale,
                          anchorStretch: !reduceMotion,
                          onPressed: onBack,
                          icon: const Icon(LucideIcons.chevronLeft),
                        ),
                      ),
                    ),
                  )
                : null),
        title:
            widget.titleContent ??
            Text(
              widget.title,
              maxLines: _headerLines(context, constraints),
              overflow: TextOverflow.ellipsis,
              style: _titleStyle(context),
            ),
        actions:
            (widget.actions == null || widget.actions!.isEmpty) &&
                widget.trailingAction == null
            ? null
            : [
                if (widget.actions != null && widget.actions!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      right: widget.trailingAction == null
                          ? DesignTokens.spacingZero
                          : DesignTokens.spacingXs,
                    ),
                    child: Center(
                      child: GlassToolbarGroup(children: widget.actions!),
                    ),
                  ),
                if (widget.trailingAction != null)
                  Center(child: widget.trailingAction!),
                const SizedBox(width: DesignTokens.spacingMd),
              ],
      );
      return Scaffold(
        backgroundColor: widget.backgroundColor,
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: PreferredSize(
          preferredSize: appBar.preferredSize,
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
            onVerticalDragUpdate: (details) => _headerDrag?.update(details),
            onVerticalDragEnd: (details) => _headerDrag?.end(details),
            onVerticalDragCancel: () => _headerDrag?.cancel(),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.componentPageContentMaxWidth,
                ),
                child: GlassSurfaceGroup(child: appBar),
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
                            if (notification.metrics.axis == Axis.vertical &&
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
          ),
        ),
        bottomNavigationBar: widget.bottom == null
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
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
                        child: Glass(
                          radius: widget.bottomRadius,
                          padding: const EdgeInsets.all(DesignTokens.spacingSm),
                          child: SizedBox(
                            width: double.infinity,
                            child: widget.bottom!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
