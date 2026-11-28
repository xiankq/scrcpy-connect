import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/models/remote_control_intent.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/desktop_remote_window.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/platform/window_host_provider.dart';
import 'package:scrcpy_connect/router/mobile_remote_capabilities.dart';
import 'package:scrcpy_connect/router/mobile_remote_window.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

typedef RemoteWindowTarget = ({String deviceId, String? packageName});

/// Keeps control navigation alive alongside the workbench in the same session.
class RemoteWindows extends StatefulWidget {
  const RemoteWindows({
    super.key,
    required this.router,
    required this.child,
    this.desktopWindow = false,
    this.mobileWindow = false,
  });

  final GoRouter router;
  final Widget child;
  final bool desktopWindow;
  final bool mobileWindow;

  static RemoteWindowsState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RemoteWindowsScope>()?.state;

  static bool isVisible(BuildContext context) =>
      RemoteWindowScope.of(context)?.focused ??
      context
          .dependOnInheritedWidgetOfExactType<_RemoteWindowsScope>()
          ?.workbenchVisible ??
      true;

  static bool hasWindows(BuildContext context) =>
      (context
              .dependOnInheritedWidgetOfExactType<_RemoteWindowsScope>()
              ?.count ??
          0) >
      0;

  @override
  State<RemoteWindows> createState() => RemoteWindowsState();
}

class RemoteWindowsState extends State<RemoteWindows>
    with WidgetsBindingObserver {
  final _windows = <RemoteWindowTarget, RemoteWindowPane>{};
  RemoteWindowPane? _active;
  (RemoteWindowPane, RemoteWindowPane)? _pair;
  bool _workbenchFocused = true;

  ScaffoldMessengerState? get workbenchMessenger =>
      ScaffoldMessenger.maybeOf(context);

  BuildContext? get workbenchContext =>
      widget.router.routerDelegate.navigatorKey.currentContext;

  void _activate(RemoteWindowPane? pane) {
    if (pane?.mobile case final window?) {
      unawaited(window.show());
      return;
    }
    if (pane?.desktop case final window?) {
      window.activate();
      return;
    }
    if (_active == pane) return;
    setState(() {
      if (pane != null && _pair?.$1 != pane && _pair?.$2 != pane) {
        _pair = null;
      }
      _active = pane;
    });
    SystemChrome.setEnabledSystemUIMode(
      pane == null ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.router.routeInformationProvider.addListener(showWorkbench);
    if (widget.mobileWindow) {
      PlatformWindowHost.lifecycle.setMethodCallHandler((call) async {
        if (call.method != 'destroyed' || !mounted) return;
        final pane = _windows.values
            .where((pane) => pane.mobile?.id == call.arguments)
            .firstOrNull;
        if (pane == null) return;
        final window = pane.mobile!;
        window.rendererDestroyed();
        remove(pane);
        try {
          await window.stop();
        } on RequestFailure catch (failure) {
          if (failure.code != 'session_not_found') rethrow;
        }
      });
    }
    if (widget.desktopWindow) WidgetsBinding.instance.addObserver(this);
    if (widget.desktopWindow && DesktopRemoteWindow.sharesAccessibilityTree) {
      SemanticsBinding.instance.addSemanticsEnabledListener(_semanticsChanged);
    }
  }

  void _semanticsChanged() {
    if (!SemanticsBinding.instance.semanticsEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !SemanticsBinding.instance.semanticsEnabled) return;
      final native = <RemoteWindowPane, DesktopRemoteWindow>{
        for (final pane in _windows.values) pane: ?pane.desktop,
      };
      if (native.isEmpty) return;
      final focused = native.entries
          .where((entry) => entry.value.focused)
          .firstOrNull
          ?.key;
      setState(() {
        for (final pane in native.keys) {
          pane.desktop = null;
        }
        if (focused != null) {
          _pair = null;
          _active = focused;
        }
        _workbenchFocused = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final window in native.values) {
          window.dispose();
        }
      });
    });
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    final ownView = View.of(context).viewId;
    final focused = event.state == ViewFocusState.focused;
    if (!focused && event.viewId != ownView) return;
    setState(() => _workbenchFocused = focused && event.viewId == ownView);
  }

  @override
  void dispose() {
    widget.router.routeInformationProvider.removeListener(showWorkbench);
    if (widget.mobileWindow) {
      PlatformWindowHost.lifecycle.setMethodCallHandler(null);
    }
    WidgetsBinding.instance.removeObserver(this);
    if (widget.desktopWindow && DesktopRemoteWindow.sharesAccessibilityTree) {
      SemanticsBinding.instance.removeSemanticsEnabledListener(
        _semanticsChanged,
      );
    }
    final panes = _windows.values.toList();
    _windows.clear();
    for (final pane in panes) {
      pane.dispose();
    }
    super.dispose();
  }

  bool willCreateDesktopWindow(RemoteWindowTarget target) =>
      !_windows.containsKey(target) &&
      widget.desktopWindow &&
      !(DesktopRemoteWindow.sharesAccessibilityTree &&
          SemanticsBinding.instance.semanticsEnabled);

  bool willCreateMobileWindow(RemoteWindowTarget target) =>
      widget.mobileWindow && !_windows.containsKey(target);

  Future<void> open(
    RemoteWindowTarget target,
    GoRouter Function(RouteObserver<ModalRoute<dynamic>>) createRouter, {
    required String workbenchLocation,
    String? appName,
    RemoteControlIntent? action,
    bool keyboard = false,
    Size? screenSize,
    double navigationHeight = 0,
    String? mobileLocation,
    RemoteLaunchIntent? mobileExtra,
    Future<void> Function(BuildContext, MobileRemoteOpen)? openMobileTarget,
  }) async {
    var pane = _windows[target];
    if (pane == null) {
      final observer = RouteObserver<ModalRoute<dynamic>>();
      final created = RemoteWindowPane(
        target: target,
        workbenchLocation: workbenchLocation,
        appName: target.packageName == null ? null : appName,
        observer: observer,
        router: createRouter(observer),
        dispatcher: widget.router.backButtonDispatcher
            .createChildBackButtonDispatcher(),
      );
      if (willCreateDesktopWindow(target) &&
          (target.packageName != null || screenSize != null)) {
        try {
          late final DesktopRemoteWindow window;
          window = DesktopRemoteWindow(
            navigationHeight,
            title: created.title,
            screenSize: screenSize,
            close: () => unawaited(_close(created)),
            destroyed: () {
              if (identical(created.desktop, window)) remove(created);
            },
          );
          created.desktop = window;
        } on UnsupportedError {
          // Keep the same target in the workbench if this embedder has no window support.
        }
      }
      if (mobileLocation != null &&
          openMobileTarget != null &&
          willCreateMobileWindow(target)) {
        final providers = ProviderScope.containerOf(context, listen: false);
        final host = providers.read(platformWindowHostProvider);
        final device = providers
            .read(deviceListProvider)
            .devices
            .where((device) => device.id == target.deviceId)
            .firstOrNull;
        if (device != null) created.deviceLabel = deviceName(device);
        final native = MobileRemoteWindow(
          deviceId: target.deviceId,
          title: created.title,
          location: mobileLocation,
          extra: mobileExtra,
          aspectRatio: screenSize?.aspectRatio,
          navigationHeight: navigationHeight,
          host: host,
          providers: providers,
          entries: _mobileEntries,
          activate: _activateMobileEntry,
          workbench: () async {
            showWorkbench();
            if (widget.router.state.uri.path != workbenchLocation) {
              widget.router.go(workbenchLocation);
            }
            await host.showWorkbench();
          },
          open: (request) async {
            final workbench = workbenchContext;
            if (workbench == null) return;
            await openMobileTarget(workbench, request);
            if (mounted &&
                _active?.target ==
                    (
                      deviceId: request.deviceId,
                      packageName: request.onPhoneScreen
                          ? null
                          : request.packageName,
                    )) {
              await host.showWorkbench();
            }
          },
        );
        created.mobile = native;
        created.close = ({bool movingToPhone = false}) async {
          await native.stop();
          remove(created);
          await host.close(native.id);
          return true;
        };
        setState(() => _windows[target] = created);
        if (await native.show()) return;
        if (!mounted || _windows[target] != created) return;
        native.dispose();
        created.mobile = null;
        created.close = null;
        unawaited(host.close(native.id));
      } else {
        setState(() => _windows[target] = created);
      }
      pane = created;
    }
    final opened = pane;
    if (appName != null || action != null || keyboard) {
      setState(() {
        if (appName != null && target.packageName != null) {
          opened.appName = appName;
        }
        if (action != null || keyboard) {
          opened.request = RemoteWindowRequest(action, keyboard);
        }
      });
      opened.desktop?.setTitle(opened.title);
    }
    if (opened.mobile case final mobile?) {
      if (action != null || keyboard) {
        mobile.request((action: action, keyboard: keyboard));
      }
      await mobile.show();
    } else {
      _activate(opened);
    }
  }

  List<MobileRemoteEntry> _mobileEntries() => [
    for (final pane in _windows.values)
      (
        windowId: pane.switcherId,
        deviceId: pane.target.deviceId,
        deviceName: pane.deviceLabel ?? '设备',
        packageName: pane.target.packageName,
        name: pane.appName,
      ),
  ];

  Future<void> _activateMobileEntry(String id) async {
    final pane = _windows.values
        .where((pane) => pane.switcherId == id)
        .firstOrNull;
    if (pane == null) return;
    if (pane.mobile case final mobile?) {
      await mobile.show();
    } else {
      _activate(pane);
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(platformWindowHostProvider).showWorkbench();
    }
  }

  void showWorkbench() => _activate(null);

  RemoteWindowPane? windowFor(RemoteWindowTarget target) => _windows[target];

  void remove(RemoteWindowPane pane) {
    if (_windows[pane.target] != pane) return;
    final pair = _pair;
    RemoteWindowPane? other;
    setState(() {
      _windows.remove(pane.target);
      if (pair?.$1 == pane || pair?.$2 == pane) {
        other = pair?.$1 == pane ? pair?.$2 : pair?.$1;
        _pair = null;
      }
    });
    if (_active == pane) _activate(other);
    pane.mobile?.dispose();
    pane.mobile = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => pane.dispose());
  }

  Future<void> _close(RemoteWindowPane pane) async {
    if (pane.close case final close?) {
      await close();
    } else {
      remove(pane);
    }
  }

  Future<void> showSwitcher(BuildContext context) async {
    final origin = RemoteWindowScope.of(context)?.pane ?? _active;
    final canPair =
        origin != null &&
        origin.desktop == null &&
        _pairLayout(this.context.windowEnvironment) != null;
    final selected = await _chooseRemoteWindow(
      context,
      [
        for (final pane in _windows.values)
          (
            target: pane.target,
            deviceLabel: pane.deviceLabel,
            appName: pane.appName,
            selected: pane == origin,
            value: pane,
            pair:
                canPair &&
                    pane != origin &&
                    pane.desktop == null &&
                    pane.mobile == null
                ? (origin, pane)
                : null,
          ),
      ],
      workbench: origin == null ? null : this,
      showSingle: canPair && (_pair?.$1 == origin || _pair?.$2 == origin),
    );
    if (!mounted || selected == null) return;
    if (identical(selected, this) && origin != null) {
      showWorkbench();
      final location = origin.workbenchLocation;
      if (widget.router.state.uri.path != location) widget.router.go(location);
      if (origin.desktop != null) {
        await DesktopWindow.command('activate');
        if (mounted) setState(() => _workbenchFocused = true);
      }
    } else if (selected is RemoteWindowPane &&
        _windows[selected.target] == selected) {
      _activate(selected);
    } else if (selected case (
      final RemoteWindowPane first,
      final RemoteWindowPane second,
    )) {
      if (_windows[first.target] == first &&
          _windows[second.target] == second) {
        setState(() => _pair = (first, second));
        _activate(first);
      }
    } else if (selected == false) {
      setState(() => _pair = null);
    }
  }

  @override
  Widget build(BuildContext context) => _RemoteWindowsScope(
    state: this,
    count: _windows.length,
    workbenchVisible: _active == null && _workbenchFocused,
    child: ViewAnchor(
      view: ViewCollection(
        views: [
          for (final pane in _windows.values)
            if (pane.desktop case final window?)
              DesktopRemoteWindowView(
                key: ObjectKey(pane),
                window: window,
                builder: ({required visible, required focused}) =>
                    _view(pane, visible: visible, focused: focused),
              ),
        ],
      ),
      child: Builder(builder: _workbenchAndPanes),
    ),
  );

  Widget _workbenchAndPanes(BuildContext context) {
    final media = MediaQuery.of(context);
    final pair = _active == null ? null : _pair;
    final layout = pair == null ? null : _pairLayout(context.windowEnvironment);
    return Stack(
      fit: StackFit.expand,
      children: [
        _WindowVisibility(
          active: _active == null,
          child: Listener(
            onPointerDown: widget.desktopWindow
                ? (_) {
                    if (!_workbenchFocused) {
                      setState(() => _workbenchFocused = true);
                    }
                  }
                : null,
            child: widget.child,
          ),
        ),
        for (final pane in _windows.values)
          if (pane.desktop == null && pane.mobile == null)
            _inlinePane(
              pane,
              media,
              left: pane == pair?.$2 ? layout?.secondStart : null,
              right: pane == pair?.$1 && layout != null
                  ? media.size.width - layout.firstWidth
                  : null,
            ),
      ],
    );
  }

  ({double firstWidth, double secondStart})? _pairLayout(
    WindowEnvironment environment,
  ) {
    if (environment.horizontalPaneDivider != null) return null;
    final hinge = environment.verticalPaneDivider;
    if (hinge == null && !environment.isExpanded) return null;
    final first = hinge?.left ?? (environment.width - _paneGap) / 2;
    final second = hinge == null ? first + _paneGap : hinge.left + hinge.width;
    if (first - environment.insets.left < 360 ||
        environment.width - second - environment.insets.right < 360) {
      return null;
    }
    return (firstWidth: first, secondStart: second);
  }

  Widget _inlinePane(
    RemoteWindowPane pane,
    MediaQueryData media, {
    double? left,
    double? right,
  }) {
    final paired = left != null || right != null;
    final focused = _active == pane;
    final visible = focused || paired;
    EdgeInsets paneInsets(EdgeInsets insets) => insets.copyWith(
      left: left == null ? insets.left : 0,
      right: right == null ? insets.right : 0,
    );
    return Positioned(
      key: ObjectKey(pane),
      top: 0,
      bottom: 0,
      left: left ?? 0,
      right: right ?? 0,
      child: _WindowVisibility(
        active: visible,
        focused: focused,
        child: ClipRect(
          child: Listener(
            onPointerDown: paired && !focused ? (_) => _activate(pane) : null,
            child: MediaQuery(
              data: paired
                  ? media.copyWith(
                      size: Size(
                        media.size.width - (left ?? 0) - (right ?? 0),
                        media.size.height,
                      ),
                      padding: paneInsets(media.padding),
                      viewPadding: paneInsets(media.viewPadding),
                      viewInsets: paneInsets(media.viewInsets),
                      displayFeatures: const [],
                    )
                  : media,
              child: _view(pane, visible: visible, focused: focused),
            ),
          ),
        ),
      ),
    );
  }

  Widget _view(
    RemoteWindowPane pane, {
    required bool visible,
    required bool focused,
  }) => RemoteWindowScope(
    key: GlobalObjectKey(pane),
    pane: pane,
    active: visible,
    focused: focused,
    request: pane.request,
    child: ScaffoldMessenger(
      child: Router(
        routeInformationProvider: pane.routeInformation,
        routeInformationParser: pane.router.routeInformationParser,
        routerDelegate: pane.router.routerDelegate,
        backButtonDispatcher: focused
            ? (pane.dispatcher..takePriority())
            : null,
      ),
    ),
  );
}

class _WindowVisibility extends StatelessWidget {
  const _WindowVisibility({
    required this.active,
    this.focused = true,
    required this.child,
  });

  final bool active;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !active,
    child: ExcludeFocus(
      excluding: !active || !focused,
      child: TickerMode(enabled: active, child: child),
    ),
  );
}

class _RemoteWindowsScope extends InheritedWidget {
  const _RemoteWindowsScope({
    required this.state,
    required this.count,
    required this.workbenchVisible,
    required super.child,
  });

  final RemoteWindowsState state;
  final int count;
  final bool workbenchVisible;

  @override
  bool updateShouldNotify(_RemoteWindowsScope oldWidget) =>
      count != oldWidget.count ||
      workbenchVisible != oldWidget.workbenchVisible;
}

class RemoteWindowsButton extends StatelessWidget {
  const RemoteWindowsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RemoteWindowsScope>();
    if (scope == null || scope.count == 0) return const SizedBox.shrink();
    return GlassActionIcon(
      tooltip: '远控窗口',
      icon: const Icon(LucideIcons.layers),
      onPressed: () => scope.state.showSwitcher(context),
    );
  }
}

class RemoteWindowRequest {
  RemoteWindowRequest(this.action, this.keyboard);
  final RemoteControlIntent? action;
  final bool keyboard;
}

class RemoteWindowPane {
  RemoteWindowPane({
    required this.target,
    required this.workbenchLocation,
    required this.appName,
    required this.observer,
    required this.router,
    required this.dispatcher,
  });

  final RemoteWindowTarget target;
  final String workbenchLocation;
  String? appName;
  final RouteObserver<ModalRoute<dynamic>> observer;
  final GoRouter router;
  late final routeInformation = _WindowRouteInformation(
    router.routeInformationProvider,
  );
  final ChildBackButtonDispatcher dispatcher;
  String? deviceLabel;
  RemoteWindowRequest? request;
  Future<bool> Function({bool movingToPhone})? close;
  DesktopRemoteWindow? desktop;
  MobileRemoteWindow? mobile;

  String get switcherId => mobile?.id ?? router.hashCode.toString();

  String get title =>
      '${deviceLabel ?? '邻接'} · ${appName ?? target.packageName ?? '手机屏幕'}';

  void dispose() {
    desktop?.dispose();
    mobile?.dispose();
    router.dispose();
  }
}

typedef _WindowPickerEntry = ({
  RemoteWindowTarget target,
  String? deviceLabel,
  String? appName,
  bool selected,
  Object value,
  Object? pair,
});

Future<void> showMobileRemoteSwitcher(
  BuildContext context,
  MobileRemoteClient client,
) async {
  final windows = await client.entries();
  if (!context.mounted) return;
  final result = await _chooseRemoteWindow(context, [
    for (final entry in windows)
      (
        target: (deviceId: entry.deviceId, packageName: entry.packageName),
        deviceLabel: entry.deviceName,
        appName: entry.name,
        selected: entry.windowId == client.windowId,
        value: entry.windowId,
        pair: null,
      ),
  ], workbench: '');
  if (result case final String id) {
    if (id.isEmpty) {
      await client.workbench();
    } else {
      await client.activate(id);
    }
  }
}

Future<Object?> _chooseRemoteWindow(
  BuildContext context,
  List<_WindowPickerEntry> entries, {
  Object? workbench,
  bool showSingle = false,
}) {
  final groups = <String, List<_WindowPickerEntry>>{};
  for (final entry in entries) {
    (groups[entry.target.deviceId] ??= []).add(entry);
  }
  return showAppModalSheet<Object>(
    context: context,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontal = DesignTokens.componentSheetPadding;
            final width = constraints.maxWidth - horizontal * 2;
            final columns = (width / _appCellWidth).floor().clamp(1, 6);
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsetsDirectional.fromSTEB(
                horizontal,
                DesignTokens.spacingSm,
                horizontal,
                horizontal,
              ),
              children: [
                Semantics(
                  header: true,
                  child: Text('远控窗口', style: AppTypography.of(context).title3),
                ),
                if (workbench != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      role: AppButtonRole.text,
                      size: AppButtonSize.section,
                      icon: LucideIcons.layoutDashboard,
                      label: '返回工作台',
                      onPressed: () => Navigator.pop(context, workbench),
                    ),
                  ),
                if (showSingle)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      role: AppButtonRole.text,
                      size: AppButtonSize.section,
                      icon: LucideIcons.square,
                      label: '仅显示当前画面',
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                for (final group in groups.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: DesignTokens.spacingLg,
                      bottom: DesignTokens.spacingSm,
                    ),
                    child: Text(
                      group
                              .map((entry) => entry.deviceLabel)
                              .nonNulls
                              .firstOrNull ??
                          '正在读取设备',
                      style: AppTypography.of(context).headline
                          .copyWith(color: AppColors.of(context).textSecondary),
                    ),
                  ),
                  Wrap(
                    runSpacing: DesignTokens.spacingSm,
                    children: [
                      for (final entry in [
                        ...group.where(
                          (entry) => entry.target.packageName == null,
                        ),
                        ...group.where(
                          (entry) => entry.target.packageName != null,
                        ),
                      ])
                        SizedBox(
                          width: width / columns,
                          child: _RemoteWindowTile(
                            key: ValueKey(entry.target),
                            target: entry.target,
                            appName: entry.appName,
                            selected: entry.selected,
                            onOpen: () => Navigator.pop(context, entry.value),
                            onPair: entry.pair == null
                                ? null
                                : () => Navigator.pop(context, entry.pair),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _RemoteWindowTile extends ConsumerWidget {
  const _RemoteWindowTile({
    super.key,
    required this.target,
    required this.appName,
    required this.selected,
    required this.onOpen,
    required this.onPair,
  });

  final RemoteWindowTarget target;
  final String? appName;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onPair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final package = target.packageName;
    final label =
        appName ??
        (package == null
            ? '手机屏幕'
            : ref.watch(
                    installedDeviceAppsProvider(target.deviceId).select(
                      (apps) => apps.value
                          ?.where((app) => app.packageName == package)
                          .firstOrNull
                          ?.name,
                    ),
                  ) ??
                  package);
    const radius = BorderRadius.all(Radius.circular(DesignTokens.roundedMd));
    return Column(
      children: [
        Semantics(
          button: true,
          selected: selected,
          child: Tooltip(
            message: label,
            child: Material(
              color: selected
                  ? colors.primaryContainer
                  : colors.page.withAlpha(0),
              shape: const RoundedSuperellipseBorder(borderRadius: radius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                splashColor: colors.page.withAlpha(0),
                highlightColor: colors.pressed,
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingXs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (package != null)
                        Center(
                          child: PhoneAppIcon(
                            deviceId: target.deviceId,
                            packageName: package,
                          ),
                        )
                      else
                        SizedBox(
                          height: _appIconSize,
                          child: Icon(
                            AppIcons.navigationDevices,
                            color: colors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.of(context).caption.copyWith(
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onPair != null)
          SolidIconButton(
            compact: true,
            onPage: true,
            tooltip: '与当前画面并排',
            onPressed: onPair,
            icon: LucideIcons.columns2,
          ),
      ],
    );
  }
}

/// Inner routers keep their history inside their own pane.
class _WindowRouteInformation extends RouteInformationProvider {
  _WindowRouteInformation(this.source);

  final RouteInformationProvider source;

  @override
  RouteInformation get value => source.value;

  @override
  void addListener(VoidCallback listener) => source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);
}

class RemoteWindowScope extends InheritedWidget {
  const RemoteWindowScope({
    super.key,
    required this.pane,
    required this.active,
    required this.focused,
    required this.request,
    required super.child,
  });

  final RemoteWindowPane pane;
  final bool active;
  final bool focused;
  final RemoteWindowRequest? request;

  static RemoteWindowScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemoteWindowScope>();

  @override
  bool updateShouldNotify(RemoteWindowScope oldWidget) =>
      active != oldWidget.active ||
      focused != oldWidget.focused ||
      request != oldWidget.request;
}

/// 并排窗口之间的间隙（无铰链时）。
const _paneGap = DesignTokens.spacingSm;

/// 窗口选择宫格的单元宽与应用图标高（Ardot 常用应用宫格：图标 52、单元约 78）。
const _appCellWidth = 78.0;
const _appIconSize = DesignTokens.componentDeviceTileSize;
