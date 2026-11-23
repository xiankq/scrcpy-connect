import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/router/models/remote_control_intent.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

typedef RemoteWindowTarget = ({String deviceId, String? packageName});

/// Keeps control navigation alive alongside the workbench in the same session.
class RemoteWindows extends StatefulWidget {
  const RemoteWindows({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  static RemoteWindowsState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RemoteWindowsScope>()?.state;

  static bool isVisible(BuildContext context) =>
      RemoteWindowScope.of(context)?.active ??
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

class RemoteWindowsState extends State<RemoteWindows> {
  final _windows = <RemoteWindowTarget, RemoteWindowPane>{};
  RemoteWindowPane? _active;

  ScaffoldMessengerState? get workbenchMessenger =>
      ScaffoldMessenger.maybeOf(context);

  BuildContext? get workbenchContext =>
      widget.router.routerDelegate.navigatorKey.currentContext;

  void _activate(RemoteWindowPane? pane) {
    if (_active == pane) return;
    setState(() => _active = pane);
    SystemChrome.setEnabledSystemUIMode(
      pane == null ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.router.routeInformationProvider.addListener(showWorkbench);
  }

  @override
  void dispose() {
    widget.router.routeInformationProvider.removeListener(showWorkbench);
    for (final pane in _windows.values) {
      pane.router.dispose();
    }
    super.dispose();
  }

  void open(
    RemoteWindowTarget target,
    GoRouter Function(RouteObserver<ModalRoute<dynamic>>) createRouter, {
    required String workbenchLocation,
    String? appName,
    RemoteControlIntent? action,
    bool keyboard = false,
  }) {
    final pane = _windows.putIfAbsent(target, () {
      final observer = RouteObserver<ModalRoute<dynamic>>();
      return RemoteWindowPane(
        target: target,
        workbenchLocation: workbenchLocation,
        appName: appName,
        observer: observer,
        router: createRouter(observer),
        dispatcher: widget.router.backButtonDispatcher
            .createChildBackButtonDispatcher(),
      );
    });
    if (appName != null) pane.appName = appName;
    if (action != null || keyboard) {
      setState(() => pane.request = RemoteWindowRequest(action, keyboard));
    }
    _activate(pane);
  }

  void showWorkbench() => _activate(null);

  RemoteWindowPane? windowFor(RemoteWindowTarget target) => _windows[target];

  void remove(RemoteWindowPane pane) {
    if (_windows[pane.target] != pane) return;
    setState(() => _windows.remove(pane.target));
    if (_active == pane) showWorkbench();
    WidgetsBinding.instance.addPostFrameCallback((_) => pane.router.dispose());
  }

  Future<void> showSwitcher(BuildContext context) async {
    final origin = _active;
    final selected = await showAppModalSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacingSm,
            ),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  DesignTokens.spacingMd,
                  DesignTokens.spacingSm,
                  DesignTokens.spacingMd,
                  DesignTokens.spacingSm,
                ),
                child: Text(
                  '远控窗口',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (origin != null)
                ListTile(
                  leading: const Icon(LucideIcons.layoutDashboard),
                  title: const Text('返回工作台'),
                  onTap: () => Navigator.pop(context, this),
                ),
              for (final pane in _windows.values)
                ListTile(
                  leading: Icon(
                    pane.target.packageName == null
                        ? LucideIcons.smartphone
                        : LucideIcons.appWindow,
                  ),
                  title: Text(
                    pane.appName ?? pane.target.packageName ?? '手机屏幕',
                  ),
                  subtitle: Text(pane.deviceLabel ?? '正在读取设备'),
                  selected: pane == origin,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  trailing: IconButton(
                    tooltip: '关闭窗口',
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context, (pane, true)),
                  ),
                  onTap: () => Navigator.pop(context, pane),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (identical(selected, this) && origin != null) {
      showWorkbench();
      final location = origin.workbenchLocation;
      if (widget.router.state.uri.path != location) widget.router.go(location);
    } else if (selected is RemoteWindowPane &&
        _windows[selected.target] == selected) {
      _activate(selected);
    } else if (selected case (final RemoteWindowPane pane, true)) {
      if (pane.close case final close?) {
        await close();
      } else {
        remove(pane);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _RemoteWindowsScope(
    state: this,
    count: _windows.length,
    workbenchVisible: _active == null,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _WindowVisibility(active: _active == null, child: widget.child),
        for (final pane in _windows.values)
          _WindowVisibility(
            key: ObjectKey(pane),
            active: _active == pane,
            child: RemoteWindowScope(
              pane: pane,
              active: _active == pane,
              request: pane.request,
              child: ScaffoldMessenger(
                child: Router(
                  routeInformationProvider: pane.routeInformation,
                  routeInformationParser: pane.router.routeInformationParser,
                  routerDelegate: pane.router.routerDelegate,
                  backButtonDispatcher: _active == pane
                      ? (pane.dispatcher..takePriority())
                      : null,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _WindowVisibility extends StatelessWidget {
  const _WindowVisibility({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !active,
    child: ExcludeFocus(
      excluding: !active,
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
  Future<bool> Function()? close;
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
    required this.request,
    required super.child,
  });

  final RemoteWindowPane pane;
  final bool active;
  final RemoteWindowRequest? request;

  static RemoteWindowScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemoteWindowScope>();

  @override
  bool updateShouldNotify(RemoteWindowScope oldWidget) =>
      active != oldWidget.active || request != oldWidget.request;
}
