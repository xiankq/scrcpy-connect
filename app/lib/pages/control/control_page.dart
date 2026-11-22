import 'dart:async';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/control/models/app_launch_record.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/remote_display_settings.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/pages/control/remote_session_lifecycle.dart';
import 'package:scrcpy_connect/pages/control/remote_display_sizing.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/remote_screen_state.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/pages/control/widgets/exit_handle.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_audio_control.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_navigation_bar.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_notices.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_recovery_panel.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_surface.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/models/remote_control_intent.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

import 'package:scrcpy_connect/widgets/dialogs.dart' show confirm, appSnackBar;
import 'package:scrcpy_connect/widgets/remote_failure.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

class ControlPage extends ConsumerStatefulWidget {
  const ControlPage({
    super.key,
    required this.device,
    this.packageName,
    this.existingSession,
    this.requestKeyboard = false,
    this.initialAction,
  });
  final DeviceSnapshot device;
  final String? packageName;
  final VideoSessionView? existingSession;
  final bool requestKeyboard;
  final RemoteControlIntent? initialAction;
  @override
  ConsumerState<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends ConsumerState<ControlPage>
    with WidgetsBindingObserver, RouteAware {
  bool ime = false;
  final inputFocus = FocusNode();
  final keyboardFocus = FocusNode();
  SessionViewLease? get view => window.view;
  ModalRoute<dynamic>? observedRoute;
  RemoteWindowPane? _pane;
  var _windowActive = true;
  RemoteWindowRequest? _request;
  late RemoteControlIntent? _initialAction = widget.initialAction;
  late bool _keyboardRequested = widget.requestKeyboard;
  late final RemoteWindow window;
  RemotePresentation get presentation => window.presentation;
  late final RemoteSessionLifecycle sessionLifecycle;
  late final notices = RemoteNotices(
    presentation: presentation,
    isVisible: () =>
        mounted &&
        acceptsInput &&
        view?.isCurrent == true &&
        ModalRoute.of(context)?.isCurrent != false,
  );
  late final RemoteDisplaySettings displaySettings;
  late final RemoteDisplaySizing displaySizing;
  late final RemoteScreenState screenState;
  bool waking = false;
  bool converting = false;
  Future<void>? newWindowWake;

  Future<void> requestWake() async {
    String? currentConnection() =>
        ref
            .read(deviceListProvider)
            .devices
            .where((device) => device.id == widget.device.id)
            .firstOrNull
            ?.connectionId ??
        widget.device.connectionId;
    if (!_sourcesCurrent) return;
    final connection = currentConnection();
    final wake = ref.read(deviceWakeProvider);
    await wake.wakeDevice(widget.device.id, connectionId: connection);
    if (!_sourcesCurrent || presentation.exiting) return;
    if (connection != currentConnection() ||
        !identical(wake, ref.read(deviceWakeProvider))) {
      throw const RequestFailure('stale_connection', '点亮请求所属连接已变化，请核对当前画面。');
    }
  }

  Future<void> wakeScreen() async {
    if (!_sourcesCurrent || waking || presentation.exiting) return;
    setState(() => waking = true);
    try {
      await requestWake();
      if (!_sourcesCurrent || presentation.exiting) return;
      // 明确唤醒可以解除启动唤醒失败，但后续通用重试不能自动重放失败请求。
      newWindowWake = Future<void>.value();
      await screenState.refresh();
      if (mounted && presentation.errorCode == 'device_asleep') await start();
    } catch (failure) {
      if (mounted) {
        notices.show(remoteFailure(failure, fallback: '暂时无法确认屏幕是否已点亮。请先查看手机。'));
      }
    } finally {
      if (mounted) setState(() => waking = false);
    }
  }

  Future<void> screenshot() async {
    final owned = view;
    final id = sessionId;
    if (!_sourcesCurrent || owned?.isCurrent != true || id.isEmpty) return;
    try {
      final screenshots = ref.read(videoScreenshotsProvider);
      final result = await screenshots.captureScreenshot(id);
      if (!mounted ||
          !_sourcesCurrent ||
          view != owned ||
          sessionId != id ||
          !identical(screenshots, ref.read(videoScreenshotsProvider))) {
        return;
      }
      await ScreenshotRoute(
        deviceId: widget.device.id,
        $extra: result,
      ).push<void>(context);
    } catch (failure) {
      if (mounted) {
        notices.show(remoteFailure(failure, fallback: '无法截图。请等手机画面恢复后再试。'));
      }
    }
  }

  Future<void> convertToIndependent() async {
    if (converting || widget.packageName != null || !canSendInput) return;
    setState(() => converting = true);
    try {
      final package = await window.verifiedForegroundApp(
        canSendInput: () => canSendInput,
      );
      if (!mounted || package == null) return;
      await openRemoteRoute(
        context,
        deviceId: widget.device.id,
        packageName: package,
      );
    } catch (failure) {
      if (mounted && !presentation.exiting) {
        notices.show(
          remoteFailure(failure, fallback: '无法打开独立应用画面。请在手机屏幕继续操作。'),
        );
      }
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  void showKeyboard() {
    if (!canSendInput) return;
    _keyboardRequested = false;
    setState(() => ime = true);
    requestImeFocus();
  }

  bool get acceptsInput =>
      _windowActive &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  bool get canSendInput => displaySizing.canSendInput;

  late final RemoteInputOwner inputs;
  TextEditingController get text => inputs.text;
  Future<void> get inputQueue => inputs.idle;
  StreamSubscription<RuntimeEvent>? eventSubscription;
  late final Stream<RuntimeEvent> _events;
  late final VideoSessions _videos;
  late final ClipboardFocusLease _clipboardFocus;
  int _clipboardFocusRevision = 0;
  bool _retired = false;
  bool _hostDetached = false;
  bool get _sourcesCurrent => mounted && window.isCurrent;

  void _checkSources() {
    if (_retired || _sourcesCurrent) return;
    _retired = true;
    sessionLifecycle.retire();
    unawaited(eventSubscription?.cancel());
    eventSubscription = null;
    screenState.dispose();
    displaySizing.dispose();
    unawaited(window.dispose(releaseInputs));
  }

  String get sessionId => presentation.sessionId;
  @override
  void initState() {
    super.initState();
    _events = ref.read(runtimeEventsProvider);
    _videos = ref.read(videoSessionsProvider);
    _clipboardFocus = ref
        .read(clipboardFocusProvider.notifier)
        .claim(widget.device.id);
    final control = ref.read(remoteControlProvider);
    final inspection = ref.read(deviceInspectionProvider);
    final apps = ref.read(deviceAppsProvider);
    final displays = ref.read(videoDisplayProvider);
    window = RemoteWindow(
      control: control,
      videos: _videos,
      inspection: inspection,
      apps: apps,
      connectionId: () => ref
          .read(deviceListProvider)
          .devices
          .where((device) => device.id == widget.device.id)
          .firstOrNull
          ?.connectionId,
      lockOnClose: () =>
          ref
              .read(preferencesProvider)
              .values
              .deviceSettings[widget.device.id]
              ?.lockOnClose ==
          true,
      current: () =>
          mounted &&
          !_retired &&
          identical(ref.read(runtimeEventsProvider), _events) &&
          identical(ref.read(videoSessionsProvider), _videos) &&
          identical(ref.read(remoteControlProvider), control) &&
          identical(ref.read(deviceInspectionProvider), inspection) &&
          identical(ref.read(deviceAppsProvider), apps) &&
          identical(ref.read(videoDisplayProvider), displays),
      views: RemoteViewsScope.of(context),
      deviceId: widget.device.id,
    );
    inputs = RemoteInputOwner(
      window: window,
      foreground: () => acceptsInput,
      enabled: () => canSendInput,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onUnknownLaunch: detachForUnknownAppLaunch,
    );
    displaySizing = RemoteDisplaySizing(
      window: window,
      displays: displays,
      inputs: inputs,
      foreground: () => acceptsInput,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onFailure: (failure) => notices.show(
        remoteFailure(failure, fallback: '暂时无法确认屏幕比例是否已更新。请先查看手机画面。'),
      ),
    );
    screenState = RemoteScreenState(
      window: window,
      foreground: () => switch (WidgetsBinding.instance.lifecycleState) {
        null || .resumed || .inactive => true,
        _ => false,
      },
      onChanged: () {
        if (mounted) setState(() {});
      },
    )..start();
    displaySettings = RemoteDisplaySettings(
      ref.read(preferencesProvider).values.deviceSettings[widget.device.id] ??
          const DevicePreferences(),
    );
    sessionLifecycle = RemoteSessionLifecycle(
      window: window,
      packageName: widget.packageName,
      existingSession: widget.existingSession,
      foreground: () => acceptsInput,
      routeCurrent: () => ModalRoute.of(context)?.isCurrent != false,
      reconciliationPending: () =>
          ref.read(recoveryStateProvider).reconciliationPending,
      reconcile: () => ref.read(reconcileStateProvider)(),
      releaseInputs: releaseInputs,
      onFocusLost: () => updateClipboardFocus(sessionId, false),
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    inputFocus.addListener(inputFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    eventSubscription = _events.listen(onEvent);
    if (context.getInheritedWidgetOfExactType<RemoteWindowScope>() == null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (ref.read(recoveryStateProvider).reconciliationPending) {
      sessionLifecycle.markStateUnknown(initialSession: widget.existingSession);
    } else {
      unawaited(start());
    }
  }

  Future<void> start({bool recoveringConnection = false}) async {
    final opened = await sessionLifecycle.start(
      recoveringConnection: recoveringConnection,
      prepare: (current) async {
        final viewport = displaySettings.mode == 'auto'
            ? await displaySizing.initialViewport
            : Size.zero;
        if (!current()) return null;
        final dimensions = displaySettings.dimensions(viewport);
        if (_sourcesCurrent &&
            !recoveringConnection &&
            displaySettings.values.wakeOnConnect != false) {
          // 准备新窗口时消耗唤醒意图，通用重试不重放缺少回执的请求。
          await (newWindowWake ??= requestWake());
        }
        return VideoSessionPlan(
          deviceId: widget.device.id,
          packageName: widget.packageName,
          displaySize: dimensions,
          displayAuto: dimensions != null && displaySettings.mode == 'auto',
        );
      },
    );
    if (opened == null ||
        !_sourcesCurrent ||
        !presentation.acceptsStart(opened.ticket)) {
      return;
    }
    try {
      displaySizing.bind(opened.view);
      if (_keyboardRequested) showKeyboard();
      if (sessionId.isEmpty || opened.view.textureId == null) return;
      notices.consume(opened.view.wake);
      unawaited(screenState.refresh());
      if (!opened.retained) focusVisibleDevice();
      if (opened.retained) {
        await resumeView();
        if (!_sourcesCurrent || !presentation.acceptsStart(opened.ticket)) {
          return;
        }
      }
      if (presentation.covered) await pauseView();
      displaySizing.reconsider();
      await applyPendingInitialAction();
      sessionLifecycle.viewed();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        didChangeAppLifecycleState(lifecycle);
      }
    } catch (failure) {
      if (_sourcesCurrent && presentation.acceptsStart(opened.ticket)) {
        setState(
          () => presentation.failOperation(
            remoteFailure(failure),
            code: remoteFailureCode(failure),
          ),
        );
      }
    }
  }

  Future<void> applyPendingInitialAction() async {
    final action = _initialAction;
    if (action == null ||
        !presentation.takeInitialAction(
          foreground: acceptsInput,
          ownerCurrent: view?.isCurrent == true,
        )) {
      return;
    }
    // 副作用提交前先消耗意图，缺少回执意味着结果未知，恢复画面不能自动重放。
    switch (action.tool) {
      case RemoteTool.rotate:
        await send(const ControlAction.rotate());
      case RemoteTool.screen:
        await send(ControlAction.screenPower(on: action.value == 'on'));
      case RemoteTool.text:
        await send(ControlAction.text(action.value as String));
      case RemoteTool.launchApp:
        await send(ControlAction.launchApplication(action.value as String));
      case RemoteTool.key:
        final code = action.value! as int;
        await inputs.tapKey(code);
    }
  }

  void detachForUnknownAppLaunch(AppLaunchRecord record) {
    setState(() => window.detachUnknownLaunch(record, releaseInputs));
  }

  Future<void> closeUnknownAppLaunch() async {
    if (!_sourcesCurrent) return;
    if (!await confirm(
          context,
          '关闭本次打开记录？',
          '应用可能已在手机运行。仅关闭本次控制会话并保留真实任务；之后可明确选择重新打开，这可能迁移现有任务。',
          action: '确认关闭',
        ) ||
        !_sourcesCurrent) {
      return;
    }
    late final Future<bool> closing;
    setState(() {
      closing = window.closeAppLaunchRecord(
        resetInitialAction: _initialAction?.tool == RemoteTool.launchApp,
      );
    });
    final closed = await closing;
    if (!_sourcesCurrent) return;
    if (closed) newWindowWake = null;
    setState(() {});
  }

  Future<void> continueOnPhoneScreen() async {
    final package = widget.packageName;
    if (package == null ||
        presentation.appLaunchUnknown ||
        presentation.stateUnverified ||
        !await confirm(context, '在手机屏幕继续？', '将在手机屏幕继续此应用。', action: '继续打开') ||
        !mounted ||
        presentation.appLaunchUnknown ||
        presentation.stateUnverified) {
      return;
    }
    final windows = RemoteWindows.maybeOf(context);
    if (_pane == null) {
      final result = await window.close(releaseInputs);
      if (!mounted || result.closeFailure != null) return;
      RemoteRoute(
        deviceId: widget.device.id,
        $extra: RemoteLaunchIntent(
          action: RemoteControlIntent.launchApp(package),
        ),
      ).pushReplacement(context);
      return;
    }
    final deviceId = widget.device.id;
    if (!await leave() || windows?.mounted != true) return;
    final workbench = windows?.workbenchContext;
    if (workbench == null || !workbench.mounted) return;
    await openRemoteRoute(
      workbench,
      deviceId: deviceId,
      packageName: package,
      onPhoneScreen: true,
    );
  }

  void onEvent(RuntimeEvent event) {
    if (!_sourcesCurrent) return;
    switch (sessionLifecycle.acceptEvent(event)) {
      case RemoteSessionEvent.connected:
        recoverConnection();
        return;
      case RemoteSessionEvent.disconnected:
        screenState.invalidate();
        recoverConnection();
        return;
      case RemoteSessionEvent.reconciled:
        applyReconciledVisibility();
        return;
      case RemoteSessionEvent.handled:
        return;
      case RemoteSessionEvent.unhandled:
        break;
    }
    final update = window.acceptVideoEvent(event);
    if (update == null) return;
    if (update.releaseInputs) {
      unawaited(releaseInputs(binding: update.previousBinding));
    }
    if (update.changed) setState(() {});
    if (update.geometryChanged) displaySizing.observeGeometry();
    if (update.wake case final wake?) notices.consume(wake);
    focusVisibleDevice();
  }

  void applyReconciledVisibility() {
    if (presentation.stateUnverified || presentation.appLaunchUnknown) return;
    if (!presentation.covered &&
        acceptsInput &&
        !presentation.lifecyclePaused) {
      unawaited(resumeView());
    } else {
      unawaited(pauseView());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RemoteWindowScope.of(context);
    _pane = scope?.pane;
    _pane?.deviceLabel = deviceName(widget.device);
    _pane?.close = leave;
    final active = scope?.active ?? RemoteWindows.isVisible(context);
    final changed = active != _windowActive;
    _windowActive = active;
    final request = scope?.request;
    final newRequest = request != null && request != _request;
    if (newRequest) {
      _request = request;
      if (request.keyboard) _keyboardRequested = true;
      if (request.action != null) {
        _initialAction = request.action;
        presentation.allowInitialAction();
      }
    }
    final route = ModalRoute.of(context);
    if (route != observedRoute) {
      final observer = _pane?.observer ?? sessionRouteObserver;
      observer.unsubscribe(this);
      observedRoute = route;
      if (route != null) observer.subscribe(this, route);
    }
    if (changed || newRequest) {
      presentation.cover(!active || route?.isCurrent == false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_sourcesCurrent ||
            _windowActive != active ||
            presentation.exiting) {
          return;
        }
        if (changed && !active) {
          unawaited(pauseView());
        } else if (changed && !presentation.covered) {
          didPopNext();
        } else if (newRequest) {
          unawaited(applyPendingInitialAction());
        }
        if (_keyboardRequested) showKeyboard();
      });
    }
  }

  @override
  void didPushNext() {
    presentation.cover(true);
    unawaited(pauseView());
  }

  @override
  void didPopNext() {
    if (!_windowActive) return;
    presentation.cover(false);
    notices.flush();
    if (sessionLifecycle.recoveryPending) {
      recoverConnection();
    } else if (acceptsInput) {
      unawaited(resumeView());
    }
  }

  void recoverConnection() {
    if (sessionLifecycle.takeConnectionRecovery()) {
      unawaited(start(recoveringConnection: true));
    }
  }

  Future<void> pauseView() async {
    updateClipboardFocus(sessionId, false);
    final operation = window.pause(releaseInputs);
    if (mounted) setState(() {});
    await operation;
    if (mounted) setState(() {});
  }

  void focusVisibleDevice() {
    if (!_sourcesCurrent) {
      updateClipboardFocus(sessionId, false);
      return;
    }
    // 保留页面可能在其他设备可见后才完成启动或恢复，只有当前路由和会话所有者可设置焦点。
    if (!mounted ||
        presentation.exiting ||
        presentation.covered ||
        !acceptsInput ||
        presentation.stateUnverified ||
        presentation.sessionEnded ||
        view?.isCurrent != true ||
        ModalRoute.of(context)?.isCurrent == false) {
      updateClipboardFocus(sessionId, false);
      return;
    }
    updateClipboardFocus(
      sessionId,
      keyboardFocus.hasFocus && canSendInput,
      selectDevice: true,
    );
  }

  void updateClipboardFocus(
    String sessionId,
    bool focused, {
    bool selectDevice = false,
  }) {
    final revision = ++_clipboardFocusRevision;
    // 路由覆盖、换源及销毁可发生在构建中；视图先撤输入准入，焦点只发布最新意图。
    scheduleMicrotask(() {
      if (!mounted ||
          focused && _retired ||
          revision != _clipboardFocusRevision) {
        return;
      }
      _clipboardFocus.focus(sessionId, focused);
      if (selectDevice && _sourcesCurrent) {
        unawaited(
          ref.read(currentDeviceProvider.notifier).focus(widget.device.id),
        );
      }
    });
  }

  Future<void> resumeView() async {
    final operation = window.resume(
      foreground: acceptsInput,
      afterInput: inputQueue,
    );
    focusVisibleDevice();
    setState(() {});
    final outcome = await operation;
    if (!mounted) return;
    setState(() {});
    if (outcome != RemoteResumeResult.ready) return;
    if (_keyboardRequested) showKeyboard();
    focusVisibleDevice();
    notices.flush();
    await applyPendingInitialAction();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached &&
        _pane == null &&
        widget.packageName != null) {
      if (!_hostDetached) {
        _hostDetached = true;
        unawaited(window.close(releaseInputs));
      }
      return;
    }
    if (state != AppLifecycleState.resumed) unawaited(releaseInputs());
    if (state == AppLifecycleState.inactive || sessionId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      notices.flush();
      // 短暂 inactive 保留画面流但可能推迟视口调整，恢复时即使无需切换可见性也要继续调整。
      displaySizing.reconsider();
      if (!presentation.lifecycleVisibility(true)) return;
      if (sessionLifecycle.recoveryPending) {
        recoverConnection();
      } else if (!presentation.covered) {
        unawaited(resumeView());
      }
    } else {
      if (!presentation.lifecycleVisibility(false)) return;
      unawaited(pauseView());
    }
  }

  void requestImeFocus() {
    displaySizing.requestIme(MediaQuery.sizeOf(context));
    inputFocus.requestFocus();
  }

  void inputFocusChanged() {
    if (!inputFocus.hasFocus) {
      inputs.resetTextInput();
      displaySizing.finishIme();
    }
  }

  Future<void> releaseInputs({RemoteBinding? binding}) =>
      inputs.releaseInputs(binding: binding);
  Future<void> send(ControlAction action, {RemoteBinding? binding}) =>
      inputs.send(action, binding: binding);
  KeyEventResult key(FocusNode node, KeyEvent event) =>
      inputs.key(event, ime: ime);
  void pressNavigationKey(int code) {
    if (!canSendInput) return;
    unawaited(send(ControlAction.key(code, action: .down)));
    unawaited(send(ControlAction.key(code, action: .up)));
  }

  Future<bool> leave() async {
    if (presentation.exiting) return false;
    displaySizing.cancel();
    final pane = _pane;
    final windows = pane == null ? null : RemoteWindows.maybeOf(context);
    final feedback =
        windows?.workbenchMessenger ?? ScaffoldMessenger.maybeOf(context);
    final left = Completer<void>();
    final id = sessionId;
    final cleanup = window.close(releaseInputs);
    setState(() {});
    unawaited(
      cleanup.then((result) async {
        await left.future;
        if (feedback?.mounted != true) return;
        if (result.lockFailure case final failure?) {
          feedback!.showSnackBar(
            appSnackBar(
              remoteFailure(failure, fallback: '暂时无法确认手机是否已熄屏。请先查看手机。'),
            ),
          );
        }
        if (result.closeFailure case final failure?) {
          feedback!.showSnackBar(
            appSnackBar(
              remoteFailure(failure, fallback: '暂时无法确认窗口是否已关闭。请先查看「当前活动」。'),
            ),
          );
        }
        final receipt = result.receipt;
        final keepActive = receipt?.wakeCleanup;
        if (receipt?.sessionId == id &&
            keepActive != null &&
            !keepActive.cleanupConfirmed) {
          feedback!.showSnackBar(appSnackBar('窗口已关闭。请在手机上检查自动熄屏是否已恢复。'));
        }
      }),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (pane != null && windows != null) {
      await cleanup;
      if (windows.mounted) windows.remove(pane);
    } else if (mounted) {
      closePage<void>(context);
    }
    await WidgetsBinding.instance.endOfFrame;
    left.complete();
    return (await cleanup).closeFailure == null;
  }

  @override
  void dispose() {
    _retired = true;
    _pane?.close = null;
    _clipboardFocusRevision++;
    sessionLifecycle.dispose();
    notices.dispose();
    scheduleMicrotask(_clipboardFocus.dispose);
    displaySizing.dispose();
    screenState.dispose();
    final release = window.dispose(releaseInputs);
    inputs.dispose(afterInput: release);
    (_pane?.observer ?? sessionRouteObserver).unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    eventSubscription?.cancel();
    inputFocus.removeListener(inputFocusChanged);
    inputFocus.dispose();
    keyboardFocus.dispose();
    if (_pane == null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windows = RemoteWindows.maybeOf(context);
    final switchWindows = _pane != null && windows != null
        ? () => windows.showSwitcher(context)
        : null;
    ref.listen(runtimeEventsProvider, (_, _) => _checkSources());
    ref.listen(videoSessionsProvider, (_, _) => _checkSources());
    ref.listen(remoteControlProvider, (_, _) => _checkSources());
    ref.listen(deviceInspectionProvider, (_, _) => _checkSources());
    ref.listen(deviceAppsProvider, (_, _) => _checkSources());
    ref.listen(videoDisplayProvider, (_, _) => _checkSources());
    // 使用路由原始边距，Scaffold 内容区的临时缩小不能重新定义远端尺寸。
    displaySizing.observeInsets(
      keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
      windowSize: MediaQuery.sizeOf(context),
    );
    final valid =
        presentation.session?.textureId != null &&
        presentation.imageWidth > 0 &&
        presentation.imageHeight > 0;
    final loadingBackdrop =
        presentation.awaitingFirstFrame || presentation.connecting;
    final recovery = RemoteRecoveryPanel(
      presentation: presentation,
      independent: widget.packageName != null,
      waitingForFirstFrame: presentation.awaitingFirstFrame,
      onReturn: () => unawaited(leave()),
      onManageActivities: () =>
          DeviceActivitiesRoute(deviceId: widget.device.id).push<void>(context),
      onContinueOnPhoneScreen: continueOnPhoneScreen,
      onCloseUnknownAppLaunch: closeUnknownAppLaunch,
      onRetry: _retired
          ? null
          : presentation.qualityRetryable
          ? () => QualityRoute(deviceId: widget.device.id).push<void>(context)
          : presentation.appLaunchUnknown
          ? sessionLifecycle.checkAppLaunch
          : presentation.reconcileOnly
          ? sessionLifecycle.reconcileState
          : start,
    );
    // 应用消息可跨路由显示；远控使用独立消息区域，防止本机页面的结果遮住手机画面。
    final currentDevice = ref.watch(
      deviceListProvider.select(
        (state) => state.devices
            .where((device) => device.id == widget.device.id)
            .firstOrNull,
      ),
    );
    final unverified = ref.watch(
      recoveryStateProvider.select((state) => state.reconciliationPending),
    );
    final showNavigationBar = ref.watch(
      preferencesProvider.select(
        (state) =>
            state.values.deviceSettings[widget.device.id]?.showNavigationBar !=
            false,
      ),
    );
    return ScaffoldMessenger(
      key: notices.messengerKey,
      child: PopScope(
        canPop: presentation.exiting,
        onPopInvokedWithResult: (popped, _) {
          if (popped) return;
          if (loadingBackdrop) {
            unawaited(leave());
          } else {
            pressNavigationKey(4);
          }
        },
        child: Focus(
          autofocus: true,
          focusNode: keyboardFocus,
          onKeyEvent: key,
          onFocusChange: (focused) {
            updateClipboardFocus(
              sessionId,
              focused && canSendInput && !presentation.covered,
            );
            if (!focused) unawaited(releaseInputs());
          },
          child: Scaffold(
            backgroundColor: DesignTokens.colorBlack,
            resizeToAvoidBottomInset: true,
            bottomNavigationBar: showNavigationBar && !loadingBackdrop
                ? RemoteNavigationBar(
                    enabled: canSendInput,
                    onBack: () => pressNavigationKey(4),
                    onHome: () => pressNavigationKey(3),
                    onRecent: () => pressNavigationKey(187),
                  )
                : null,
            // 视频占满可绘制视口，叠加控件自行扣除安全区与系统手势边距。
            body: DesktopStage(
              child: RemoteStage(
                presentation: presentation,
                inputs: inputs,
                onViewport: displaySizing.observeViewport,
                deviceLabel: deviceName(widget.device),
                independent: widget.packageName != null,
                recovery: recovery,
                ime: ime,
                sensitive: false,
                inputFocus: inputFocus,
                needsWake:
                    screenState.screenOn == false ||
                    screenState.screenLocked == true ||
                    (screenState.screenOn == null &&
                        screenState.screenLocked == null &&
                        presentation.errorCode == 'device_asleep'),
                screenOff:
                    screenState.screenOn == false ||
                    screenState.screenOn == null &&
                        presentation.errorCode == 'device_asleep',
                onWake: waking ? null : wakeScreen,
                onClose: presentation.exiting ? null : leave,
                onSwitchWindow: switchWindows,
                controls: ExitHandle(
                  key: const ValueKey('remote-exit-handle'),
                  onExit: leave,
                  onSwitchWindow: switchWindows,
                  independent: widget.packageName != null,
                  onSleep: canSendInput ? () => pressNavigationKey(223) : null,
                  onConvert:
                      canSendInput &&
                          !converting &&
                          (int.tryParse(
                                    (widget.device.apiLevel?.toString() ?? ''),
                                  ) ??
                                  29) >=
                              29
                      ? convertToIndependent
                      : null,
                  onScreenshot: valid && view?.isCurrent == true
                      ? screenshot
                      : null,
                  onKeyboard: canSendInput ? showKeyboard : null,
                  onRotate: canSendInput
                      ? () => unawaited(send(const ControlAction.rotate()))
                      : null,
                  deviceLabel: deviceName(currentDevice ?? widget.device),
                  connectionLabel: unverified || currentDevice == null
                      ? '连接状态待核对'
                      : deviceStatusText(currentDevice),
                  soundControl: RemoteAudioControl(deviceId: widget.device.id),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
