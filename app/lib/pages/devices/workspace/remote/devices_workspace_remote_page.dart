import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/services/session_views.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart'
    show confirm, glassSnackBar;
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/remote_input.dart';
import 'package:scrcpy_connect/services/remote_display_settings.dart';

import 'remote_connection_recovery.dart';
import 'remote_presentation.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.controller,
    required this.device,
    this.packageName,
    this.existingSession,
    this.requestKeyboard = false,
    this.initialAction,
  });
  final AppController controller;
  final Json device;
  final String? packageName;
  final Json? existingSession;
  final bool requestKeyboard;
  final RemoteControlIntent? initialAction;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage>
    with WidgetsBindingObserver, RouteAware {
  bool ime = false;
  bool sensitive = false;
  final inputFocus = FocusNode();
  final keyboardFocus = FocusNode();
  static const inputSentinel = '\u200B';
  final text = TextEditingController(text: inputSentinel);
  final activePointers = <int>{};
  final pointerPositions = <int, Json>{};
  final heldKeys = <int, RemoteBinding>{};
  bool adjustmentShown = false;
  SessionView? view;
  ModalRoute<dynamic>? observedRoute;
  final presentation = RemotePresentation();
  final connectionRecovery = RemoteConnectionRecovery();
  bool restoringConnection = false;
  final remoteMessenger = GlobalKey<ScaffoldMessengerState>();
  late final void Function() releaseDeviceView;
  bool Function()? releasePhonePage;
  late final RemoteDisplaySettings displaySettings;
  final initialViewport = Completer<Size>();
  Size? displayViewport;
  ({int width, int height})? appliedDisplaySize;
  ({int width, int height})? requestedDisplaySize;
  ({int width, int height})? scheduledDisplaySize;
  RemoteBinding? scheduledDisplayBinding;
  ({int width, int height})? lastRemoteGeometry;
  bool resizingDisplay = false;
  Timer? resizeTimer;
  bool waitingForIme = false;
  Size? imeRequestedWindowSize;
  bool autoDisplay = false;

  void trace(String detail) {
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.remote ${DateTime.now().millisecondsSinceEpoch}] $detail',
      );
    }
  }

  bool get acceptsInput =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get canSendInput => !resizingDisplay && hasInputAuthority;
  bool get hasInputAuthority => presentation.canSendInput(
    foreground: acceptsInput,
    ownerCurrent: view?.isCurrent == true,
  );

  Future<void> releaseInputs() {
    resetTextInput();
    var completion = releasePointers();
    final keys = Map<int, RemoteBinding>.from(heldKeys);
    heldKeys.clear();
    if (!presentation.controlAvailable) return completion;
    for (final entry in keys.entries) {
      if (entry.value != presentation.binding) {
        continue;
      }
      completion = send(InteropCommand.sessionKey, {
        'sessionId': entry.value.$1,
        'keyCode': entry.key,
        'action': 'up',
      });
    }
    return completion;
  }

  Future<void> releasePointers() {
    final releases = pointerPositions.values.toList();
    activePointers.clear();
    pointerPositions.clear();
    if (!presentation.controlAvailable) {
      return presentation.reconcileOnly ? inputQueue : Future<void>.value();
    }
    // A physical key-up can already be queued after its held entry was
    // removed. Flush live input before stopping or replacing this session.
    Future<void> completion = inputQueue;
    for (final params in releases) {
      completion = send(InteropCommand.sessionTouch, {
        ...params,
        'action': 'cancel',
        'pressure': 0,
      });
    }
    return completion;
  }

  String previousText = inputSentinel;
  bool resettingText = false;
  StreamSubscription<Json>? eventSubscription;
  Future<void> inputQueue = Future<void>.value();
  AppController get controller => widget.controller;
  String get sessionId => presentation.sessionId;
  @override
  void initState() {
    super.initState();
    releaseDeviceView = controller.claimRemoteDeviceView(
      value(widget.device, 'id'),
    );
    if (widget.packageName == null) {
      releasePhonePage = controller.claimPhoneControlPage(
        value(widget.device, 'id'),
      );
    }
    displaySettings = RemoteDisplaySettings(
      jsonObject(
        jsonObject(controller.snapshot().settings['deviceSettings'])[value(
          widget.device,
          'id',
        )],
      ),
    );
    // IMEs can finish composition without changing text; onChanged misses it.
    text.addListener(textChanged);
    inputFocus.addListener(inputFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    eventSubscription = controller.eventStream().listen(onEvent);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (controller.snapshot().reconciliationPending) {
      markStateUnknown(initialSession: widget.existingSession);
    } else {
      unawaited(start());
    }
  }

  Future<void> start({bool recoveringConnection = false}) async {
    if (presentation.appLaunchUnknown) {
      await checkAppLaunch();
      return;
    }
    if ((!recoveringConnection && presentation.reconcileOnly) ||
        controller.snapshot().reconciliationPending) {
      await reconcileState();
      return;
    }
    late final RemoteStartTicket attempt;
    restoringConnection = recoveringConnection;
    trace(
      'start.begin lifecycle=${WidgetsBinding.instance.lifecycleState?.name}',
    );
    setState(() => attempt = presentation.beginStart());
    var submittedAppStart = false;
    try {
      await releaseInputs();
      if (!mounted || !presentation.acceptsStart(attempt)) {
        return;
      }
      if (deferConnectionStart(recoveringConnection)) return;
      presentation.replaceBinding();
      Json? retained = recoveringConnection ? null : widget.existingSession;
      if (retained == null) {
        final listed = objects(
          (await controller.execute(InteropCommand.sessionList, {
            'deviceId': widget.device['id'],
          }))['sessions'],
        );
        final matches = listed.where(
          (item) =>
              item['deviceId'] == widget.device['id'] &&
              item['packageName'] == widget.packageName &&
              (item['launchOutcome'] == 'unknown' ||
                  !['stopped', 'failed', 'error'].contains(item['status'])),
        );
        retained = matches.firstOrNull;
      }
      if (!mounted || !presentation.acceptsStart(attempt)) {
        return;
      }
      if (deferConnectionStart(recoveringConnection)) return;
      if (retained?['launchOutcome'] == 'unknown') {
        showUnknownAppLaunch(retained!);
        return;
      }
      submittedAppStart = retained == null && widget.packageName != null;
      final viewport = displaySettings.mode == 'auto'
          ? await initialViewport.future
          : Size.zero;
      if (!mounted || !presentation.acceptsStart(attempt)) return;
      final dimensions = displaySettings.dimensions(viewport);
      final result =
          retained ??
          await controller.execute(InteropCommand.sessionStart, {
            'deviceId': widget.device['id'],
            if (widget.packageName != null) 'packageName': widget.packageName,
            if (widget.packageName == null)
              'keepActive': displaySettings.values['stayAwake'] == true,
            if (dimensions != null) ...{
              'displayWidth': dimensions.width,
              'displayHeight': dimensions.height,
              'displayAuto': displaySettings.mode == 'auto',
            },
          });
      if (!mounted || !presentation.acceptsStart(attempt)) {
        if (mounted && presentation.requiresVerification(attempt)) {
          // The launch was already submitted. Its late result is an identity
          // to verify, never a reason to launch or stop the task again.
          if (sessionId.isEmpty) {
            setState(() => presentation.retainUnverifiedStart(result));
          }
          return;
        }
        if (retained == null) {
          final staleId = value(result, 'sessionId', value(result, 'id'));
          if (staleId.isNotEmpty && staleId != sessionId) {
            try {
              await controller.execute(InteropCommand.sessionStop, {
                'sessionId': staleId,
                'keepTask': true,
                if (widget.packageName != null) 'keepLaunchRecord': true,
              });
            } catch (_) {
              /* A late response cannot recreate a disposed view. */
            }
          }
        }
        return;
      }
      trace(
        'start.return status=${value(result, 'status')} hasTexture=${result['textureId'] != null} boundBefore=${sessionId.isNotEmpty} lifecycle=${WidgetsBinding.instance.lifecycleState?.name}',
      );
      setState(() {
        autoDisplay = result['displayAuto'] == true;
        final size = jsonObject(result['displaySize']);
        if (size['width'] is int && size['height'] is int) {
          appliedDisplaySize = (
            width: size['width'] as int,
            height: size['height'] as int,
          );
          requestedDisplaySize = appliedDisplaySize;
        }
        presentation.bindStart(
          result,
          retained: retained != null,
          recoveringConnection: recoveringConnection,
          submittedAppStart: submittedAppStart,
        );
        if (widget.requestKeyboard && result['textureId'] != null) ime = true;
      });
      if (ime && widget.requestKeyboard) requestImeFocus();
      if (sessionId.isEmpty || result['textureId'] == null) return;
      view = controller.claimSessionView(
        sessionId,
        visible: result['status'] != 'paused',
      );
      if (retained == null) {
        focusVisibleDevice();
      }
      if (retained != null) {
        await resumeView();
        if (!mounted || !presentation.acceptsStart(attempt)) {
          return;
        }
      }
      if (presentation.covered) await pauseView();
      if (displayViewport != null) observeViewport(displayViewport!);
      await applyPendingInitialAction();
      if (widget.packageName == null && !presentation.appLaunchUnknown) {
        connectionRecovery.viewed();
      }

      trace('start.bound paused=${presentation.paused}');
      // The bridge returns this texture only after actual decoded pixels have
      // been read. Earlier output events can precede this page binding.
      if (result['textureId'] != null) showResourceAdjustment();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        didChangeAppLifecycleState(lifecycle);
      }
    } catch (e) {
      if (mounted && presentation.acceptsStart(attempt)) {
        setState(
          () => presentation.failStart(
            remoteFailure(e),
            remoteFailureCode(e),
            submittedAppStart: submittedAppStart,
            details: e is RequestFailure ? jsonObject(e.details) : {},
          ),
        );
      }
    } finally {
      if (presentation.isLatestStart(attempt)) restoringConnection = false;
    }
  }

  bool get connectionStartAllowed =>
      mounted &&
      presentation.canRecoverConnection(
        foreground: acceptsInput,
        phoneScreen: widget.packageName == null,
        reconciliationPending: controller.snapshot().reconciliationPending,
        routeCurrent: ModalRoute.of(context)?.isCurrent != false,
      );

  bool deferConnectionStart(bool recovering) {
    if (!recovering || connectionStartAllowed) return false;
    connectionRecovery.defer();
    setState(() => presentation.deferStart());
    return true;
  }

  Future<void> applyPendingInitialAction() async {
    final action = widget.initialAction;
    if (action == null ||
        !presentation.takeInitialAction(
          foreground: acceptsInput,
          ownerCurrent: view?.isCurrent == true,
        )) {
      return;
    }
    // Consume the intent before submitting any side effect. A missing receipt
    // leaves an unknown outcome and must never turn a resume into a replay.
    switch (action.tool) {
      case RemoteTool.rotate:
        await send(InteropCommand.sessionRotate, {});
      case RemoteTool.screen:
        await send(InteropCommand.sessionScreen, {'mode': action.value});
      case RemoteTool.text:
        await send(InteropCommand.sessionText, {'text': action.value});
      case RemoteTool.launchApp:
        await send(InteropCommand.sessionLaunch, {
          'deviceId': widget.device['id'],
          'packageName': action.value,
        });
      case RemoteTool.key:
        final code = action.value! as int;
        heldKeys[code] = presentation.binding;
        try {
          await send(InteropCommand.sessionKey, {
            'keyCode': code,
            'action': 'down',
          });
        } finally {
          heldKeys.remove(code);
          await send(InteropCommand.sessionKey, {
            'keyCode': code,
            'action': 'up',
          });
        }
    }
  }

  void showUnknownAppLaunch(Json record) {
    setState(() => presentation.showUnknownAppLaunch(record));
  }

  void detachForUnknownAppLaunch(Json record) {
    // Only this exact outgoing binding may drain cleanup after the page adopts
    // the operation record. New input still needs the current live binding.
    final outgoing = presentation.permitDetachedCleanup();
    final releases = releaseInputs().whenComplete(() {
      presentation.finishDetachedCleanup(outgoing);
    });
    final owned = view;
    view = null;
    presentation.detachBinding();
    if (owned != null) {
      // Pause belongs to the captured view, even after adopting the record.
      // A lost control stream may reject pause; it cannot erase launch evidence.
      unawaited(
        owned
            .release(afterInput: releases)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    // Neither input receipts nor capture pause gate reviewing this fixed record.
    showUnknownAppLaunch(record);
  }

  Future<void> checkAppLaunch() async {
    setState(() => presentation.checking());
    try {
      final listed = objects(
        (await controller.execute(InteropCommand.sessionList, {
          'deviceId': widget.device['id'],
        }))['sessions'],
      );
      if (!mounted || presentation.exiting) return;
      final record = listed
          .where(
            (item) => sessionId.isNotEmpty
                ? value(item, 'sessionId', value(item, 'id')) == sessionId
                : item['deviceId'] == widget.device['id'] &&
                      item['packageName'] == widget.packageName,
          )
          .firstOrNull;
      showUnknownAppLaunch(record ?? presentation.session ?? {});
    } catch (failure) {
      if (mounted && !presentation.exiting) {
        setState(() {
          presentation.failOperation(remoteFailure(failure));
        });
      }
    }
  }

  Future<void> closeUnknownAppLaunch() async {
    if (!await confirm(
          context,
          '关闭本次打开记录？',
          '应用可能已在手机运行。仅关闭本次控制会话并保留真实任务；之后可明确选择重新打开，这可能迁移现有任务。',
          action: '确认关闭',
        ) ||
        !mounted) {
      return;
    }
    setState(() => presentation.checking());
    try {
      if (sessionId.isNotEmpty) {
        await controller.execute(InteropCommand.sessionStop, {
          'sessionId': sessionId,
          'keepTask': true,
        });
      }
      if (!mounted || presentation.exiting) return;
      setState(
        () => presentation.closeUnknownAppLaunch(
          resetInitialAction:
              widget.initialAction?.tool == RemoteTool.launchApp,
        ),
      );
    } catch (failure) {
      if (mounted && !presentation.exiting) {
        setState(() {
          presentation.failOperation(remoteFailure(failure));
        });
      }
    }
  }

  Future<void> wakeAndStart() async {
    if (!await confirm(
          context,
          '唤醒手机？',
          '这可能点亮被控手机的实体屏幕。唤醒不会绕过锁屏，请在手机上完成需要的解锁。',
          action: '唤醒手机',
        ) ||
        !mounted) {
      return;
    }
    setState(() => presentation.checking());
    try {
      await controller.execute(InteropCommand.devicesWake, {
        'deviceId': widget.device['id'],
      });
      if (mounted) await start();
    } catch (failure) {
      if (mounted) {
        setState(() {
          presentation.failOperation(
            remoteFailure(failure),
            code: remoteFailureCode(failure),
          );
        });
      }
    }
  }

  Future<void> continueOnPhoneScreen() async {
    final package = widget.packageName;
    if (package == null ||
        presentation.appLaunchUnknown ||
        presentation.stateUnverified ||
        !await confirm(
          context,
          '在手机屏幕继续？',
          '将在手机主屏打开此应用并接续真实任务，可能改变手机当前的前台应用。已打开的独立窗口可在窗口列表管理。',
          action: '继续打开',
        ) ||
        !mounted ||
        presentation.appLaunchUnknown ||
        presentation.stateUnverified) {
      return;
    }
    RemoteRoute(
      deviceId: value(widget.device, 'id'),
      $extra: RemoteLaunchIntent(
        action: RemoteControlIntent.launchApp(package),
      ),
    ).pushReplacement(context);
  }

  void onEvent(Json event) {
    if (event['type'] == 'session.disconnected' && event['data'] is Map) {
      trace('server.ended reason=${(event['data'] as Map)['reason']}');
    }
    if (!mounted) return;
    final data = event['data'] is Map<Object?, Object?>
        ? jsonObject(event['data'])
        : <String, dynamic>{};
    if ((event['type'] == 'session.stop.requested' &&
            data['sessionId'] == sessionId) ||
        (event['type'] == 'device.disconnect.requested' &&
            event['deviceId'] == widget.device['id'])) {
      connectionRecovery.stop();
      if (restoringConnection) {
        // A late list/start receipt must not undo a stop accepted while the
        // replacement has not yet acquired its new session identity.
        presentation.invalidateStart();
        restoringConnection = false;
        setState(() => presentation.deferStart());
      }
      return;
    }
    if (event['type'] == 'devices.changed' && widget.packageName == null) {
      final device = objects(data['devices'])
          .where((d) => d['id'] == widget.device['id'])
          .firstOrNull;
      if (device != null) {
        connectionRecovery.observe(
          value(device, 'status'),
          autoReconnect: device['autoReconnect'] == true,
        );
        recoverConnection();
      }
    }
    if (event['type'] == 'state.resync') {
      markStateUnknown();
      return;
    }
    if (event['type'] == 'state.resync.failed') {
      markStateUnknown(reason: value(data, 'reason', '状态检查未完成，请重试。'));
      return;
    }
    if (event['type'] == 'state.resynced') {
      applyReconciledState(data);
      return;
    }
    if (presentation.appLaunchUnknown ||
        presentation.stateUnverified ||
        (presentation.reconcileOnly && view?.isCurrent != true)) {
      return;
    }
    if (value(event, 'type').startsWith('session.')) {
      trace(
        'event type=${event['type']} status=${value(data, 'status')} bound=${sessionId.isNotEmpty} sessionMatches=${data['sessionId'] == null || data['sessionId'] == sessionId} deviceMatches=${event['deviceId'] == null || event['deviceId'] == widget.device['id']} hasTexture=${data['textureId'] != null} pausedBefore=${presentation.paused}',
      );
    }
    if (data['sessionId'] != null && data['sessionId'] != sessionId) return;
    if (event['deviceId'] != null && event['deviceId'] != widget.device['id']) {
      return;
    }
    switch (event['type']) {
      case 'session.frame':
      case 'session.output.changed':
      case 'session.output.resumed':
        if (event['type'] != 'session.frame' &&
            (data['firstFrameDecoded'] != true ||
                data['evidence'] != 'mdk.snapshot')) {
          return;
        }
        showResourceAdjustment();
        if (!presentation.output(data)) return;
        setState(() {});
        observeRemoteGeometry();
        trace(
          'frame.applied paused=${presentation.paused} hasTexture=${presentation.session?['textureId'] != null}',
        );
      case 'session.updated':
        if (presentation.updateSession(data)) unawaited(releaseInputs());
        setState(() {});
        trace('updated.applied paused=${presentation.paused}');
      case 'session.disconnected':
      case 'session.failed':
        presentation.disconnect(
          value(data, 'reason', '连接已中断，当前画面已暂停。恢复首帧后才能继续操作。'),
        );
        unawaited(releaseInputs());
        setState(() {});
      case 'session.ime':
        setState(() {
          ime = data['visible'] == true;
          sensitive = data['sensitive'] == true;
        });
        if (ime) {
          requestImeFocus();
        } else {
          waitingForIme = false;
          inputFocus.unfocus();
        }
    }
  }

  int markStateUnknown({String? reason, Json? initialSession}) {
    trace(
      'reconcile.unknown reason=$reason session=$sessionId visibility=${presentation.visibilityEpoch}',
    );
    final epoch = presentation.beginReconciliation(
      initialSession: initialSession,
      reason: reason,
    );
    unawaited(releaseInputs());
    presentation.replaceBinding();
    setState(() {});
    return epoch;
  }

  void applyReconciledState(Json snapshot) {
    final changed = presentation.reconcile(
      snapshot,
      packageName: widget.packageName,
      deviceId: widget.device['id'],
    );
    if (!changed) return;
    setState(() {});
    if (presentation.stateUnverified || presentation.appLaunchUnknown) return;
    if (!presentation.covered &&
        acceptsInput &&
        !presentation.lifecyclePaused) {
      unawaited(resumeView());
    } else {
      unawaited(pauseView());
    }
  }

  Future<void> reconcileState() async {
    final epoch = markStateUnknown();
    try {
      // The Bridge publishes state.resynced only after its full read barrier.
      // A command receipt alone must never unlock this surface.
      await controller.execute(InteropCommand.stateReconcile);
    } catch (failure) {
      if (mounted && presentation.acceptsReconciliation(epoch)) {
        setState(() => presentation.reportError(remoteFailure(failure)));
      }
    }
  }

  void showResourceAdjustment() {
    final message = value(presentation.session ?? {}, 'resourceAdjustment');
    if (adjustmentShown ||
        message.isEmpty ||
        presentation.session?['textureId'] is! int) {
      return;
    }
    adjustmentShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !presentation.exiting) {
        remoteMessenger.currentState?.showSnackBar(glassSnackBar(message));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == observedRoute) return;
    sessionRouteObserver.unsubscribe(this);
    observedRoute = route;
    if (route != null) sessionRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    presentation.cover(true);
    unawaited(pauseView());
  }

  @override
  void didPopNext() {
    presentation.cover(false);
    if (connectionRecovery.pending) {
      recoverConnection();
    } else if (acceptsInput) {
      unawaited(resumeView());
    }
  }

  void recoverConnection() {
    if (!connectionStartAllowed ||
        presentation.connecting ||
        !connectionRecovery.take()) {
      return;
    }
    // Consume the recovery intent synchronously before an asynchronous startup,
    // and never replay a tool action from the original route launch.
    presentation.suppressInitialAction();
    view?.abandonEndedSession();
    view = null;
    unawaited(start(recoveringConnection: true));
  }

  Future<void> pauseView() async {
    if (presentation.exiting || presentation.appLaunchUnknown) return;
    final owned = view;
    if (owned == null || !owned.isCurrent) return;
    final epoch = presentation.beginPause();
    final releases = releaseInputs();
    if (mounted) setState(() {});
    try {
      await owned.pause(afterInput: releases);
    } catch (failure) {
      if (mounted && presentation.acceptsVisibilityFailure(epoch)) {
        setState(() => presentation.reportError(remoteFailure(failure)));
      }
    }
  }

  void focusVisibleDevice() {
    // A retained page can finish starting or resuming after another device
    // becomes visible. Only the current route and session owner may set focus.
    if (!mounted ||
        presentation.exiting ||
        presentation.covered ||
        !acceptsInput ||
        presentation.stateUnverified ||
        presentation.sessionEnded ||
        view?.isCurrent != true ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final deviceId = value(widget.device, 'id');
    if (controller.snapshot().focusedDeviceId == deviceId) {
      return;
    }
    unawaited(controller.focusDevice(deviceId));
  }

  Future<void> resumeView() async {
    if (!presentation.canResume(foreground: acceptsInput)) return;
    var owned = view;
    if (owned == null || !owned.isCurrent) {
      owned = controller.claimSessionView(sessionId, visible: false);
      view = owned;
    }
    focusVisibleDevice();
    final epoch = presentation.beginResume();
    trace('resume.begin epoch=$epoch session=$sessionId');
    setState(() {});
    try {
      final receipt = await owned.resume(afterInput: inputQueue);
      trace(
        'resume.receipt epoch=$epoch current=${presentation.visibilityEpoch} owned=${owned.isCurrent} covered=${presentation.covered} evidence=${receipt['evidence']}',
      );
      if (!mounted) return;
      final outcome = presentation.completeResume(
        epoch,
        receipt,
        ownerCurrent: owned.isCurrent,
      );
      if (outcome == RemoteResumeResult.stale) return;
      if (outcome == RemoteResumeResult.rendererNotReady) {
        throw const RequestFailure('renderer_not_ready', '尚未确认恢复后的画面，请重新检查。');
      }
      setState(() {});
      await applyPendingInitialAction();
    } catch (failure) {
      trace(
        'resume.failed epoch=$epoch current=${presentation.visibilityEpoch} reason=$failure',
      );
      if (mounted && presentation.acceptsVisibilityFailure(epoch)) {
        setState(() {
          presentation.failOperation(remoteFailure(failure));
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(releaseInputs());
    if (state == AppLifecycleState.inactive || sessionId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      // A brief inactive transition keeps the stream live but can defer a
      // viewport adjustment. Resume it even when no visibility change is due.
      if (displayViewport != null) observeViewport(displayViewport!);
      if (!presentation.lifecycleVisibility(true)) return;
      if (connectionRecovery.pending) {
        recoverConnection();
      } else if (!presentation.covered) {
        unawaited(resumeView());
      }
    } else {
      if (!presentation.lifecycleVisibility(false)) return;
      unawaited(pauseView());
    }
  }

  Future<void> send(InteropCommand command, Json params) async {
    // Queue entries keep the binding that accepted them. A late request or
    // release must never inherit a replacement session's identity.
    final binding = presentation.binding;
    final captured = {'sessionId': binding.$1, ...params};
    inputQueue = inputQueue.then((_) async {
      if (!presentation.admitsQueuedInput(
        binding,
        command.wire,
        params,
        foreground: acceptsInput,
        ownerCurrent: view?.isCurrent == true,
      )) {
        return;
      }
      await sendNow(command.wire, captured, binding);
    });
    return inputQueue;
  }

  Future<void> sendNow(
    String command,
    Json params,
    RemoteBinding binding,
  ) async {
    trace('request.begin command=$command');
    try {
      await controller.request(command, params);
      trace('request.complete command=$command');
    } catch (e) {
      trace('request.failed command=$command kind=${e.runtimeType}');
      if (mounted &&
          !presentation.exiting &&
          params['sessionId'] == sessionId) {
        final details = e is RequestFailure
            ? jsonObject(e.details)
            : <String, dynamic>{};
        if (command == 'session.launch' &&
            remoteFailureCode(e) == 'app_launch_unknown' &&
            details['launchOutcome'] == 'unknown' &&
            details['recordOnly'] == true &&
            value(details, 'sessionId').isNotEmpty &&
            details['sessionId'] == details['launchOperationId'] &&
            details['sessionId'] != params['sessionId'] &&
            details['deviceId'] == widget.device['id'] &&
            details['packageName'] == params['packageName'] &&
            details['linkedSessionId'] == params['sessionId']) {
          detachForUnknownAppLaunch(details);
          return;
        }
        if (binding != presentation.binding) return;
        if ([
          'not_found',
          'disconnected',
          'not_connected',
          'session_required',
        ].contains(remoteFailureCode(e))) {
          presentation.revokeControl();
        }
        unawaited(releaseInputs());
        setState(() {
          presentation.failInput(remoteFailure(e), remoteFailureCode(e));
        });
      }
    }
  }

  void pointer(PointerEvent event, String action, Size viewport, Size source) {
    if (!canSendInput) {
      return;
    }
    final point = sourcePoint(event.localPosition, viewport, source);
    if (action == 'down') {
      if (point == null) return;
      activePointers.add(event.pointer);
    }
    if (!activePointers.contains(event.pointer)) return;
    if (point == null) {
      // End the remote gesture at its last valid position, then ignore this
      // physical pointer until it lifts. Re-entry must not create a new drag.
      final previous = pointerPositions.remove(event.pointer);
      activePointers.remove(event.pointer);
      if (previous != null) {
        unawaited(
          send(InteropCommand.sessionTouch, {
            ...previous,
            'action': 'cancel',
            'pressure': 0,
          }),
        );
      }
      return;
    }
    final params = <String, dynamic>{
      'action': action,
      'pointerId': event.pointer,
      'x': point.dx.round().clamp(0, source.width.round() - 1),
      'y': point.dy.round().clamp(0, source.height.round() - 1),
      'pressure': action == 'up' || action == 'cancel' ? 0 : event.pressure,
      'screenWidth': source.width.round(),
      'screenHeight': source.height.round(),
    };
    if (action == 'down' || action == 'move') {
      pointerPositions[event.pointer] = params;
    }
    unawaited(send(InteropCommand.sessionTouch, params));
    if (action == 'up' || action == 'cancel') {
      activePointers.remove(event.pointer);
      pointerPositions.remove(event.pointer);
    }
  }

  void requestImeFocus() {
    // Android reveals system bars before reporting the keyboard inset. Keep
    // the confirmed display through both parts of that transition.
    waitingForIme = true;
    imeRequestedWindowSize = MediaQuery.sizeOf(context);
    resizeTimer?.cancel();
    inputFocus.requestFocus();
  }

  bool get imeBlocksDisplaySizing =>
      waitingForIme || MediaQuery.viewInsetsOf(context).bottom > 0;

  void inputFocusChanged() {
    if (!inputFocus.hasFocus) {
      resetTextInput();
      if (mounted && waitingForIme) {
        setState(() => waitingForIme = false);
      }
    }
  }

  void resetTextInput() {
    previousText = inputSentinel;
    resettingText = true;
    text.value = const TextEditingValue(
      text: inputSentinel,
      selection: TextSelection.collapsed(offset: 1),
    );
    resettingText = false;
  }

  void textChanged() {
    if (resettingText) return;
    if (!canSendInput) {
      resetTextInput();
      return;
    }
    // Only send committed IME text; pinyin/candidate composition remains local.
    if (text.value.composing.isValid && !text.value.composing.isCollapsed) {
      return;
    }
    final next = text.text;
    final before = previousText.characters.toList();
    final after = next.characters.toList();
    var common = 0;
    while (common < before.length &&
        common < after.length &&
        before[common] == after[common]) {
      common++;
    }
    for (var i = common; i < before.length; i++) {
      unawaited(
        send(InteropCommand.sessionKey, {'keyCode': 67, 'action': 'down'}),
      );
      unawaited(
        send(InteropCommand.sessionKey, {'keyCode': 67, 'action': 'up'}),
      );
    }
    final added = after.skip(common).join().replaceAll(inputSentinel, '');
    if (added.isNotEmpty) {
      unawaited(send(InteropCommand.sessionText, {'text': added}));
    }
    previousText = next;
    // Keep one invisible local character so IME backspace can still delete
    // pre-existing remote text after the local insertion buffer is empty.
    if (next.isEmpty) {
      resetTextInput();
    }
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    final codes = {
      LogicalKeyboardKey.escape: 4,
      LogicalKeyboardKey.goBack: 4,
      LogicalKeyboardKey.enter: 66,
      LogicalKeyboardKey.backspace: 67,
      LogicalKeyboardKey.tab: 61,
      LogicalKeyboardKey.arrowUp: 19,
      LogicalKeyboardKey.arrowDown: 20,
      LogicalKeyboardKey.arrowLeft: 21,
      LogicalKeyboardKey.arrowRight: 22,
      LogicalKeyboardKey.home: 3,
      LogicalKeyboardKey.delete: 112,
    };
    final code = codes[event.logicalKey];
    if (event is KeyUpEvent && code != null) {
      final held = heldKeys.remove(code);
      if (held == null) return KeyEventResult.ignored;
      if (held == presentation.binding && presentation.controlAvailable) {
        unawaited(
          send(InteropCommand.sessionKey, {
            'sessionId': held.$1,
            'keyCode': code,
            'action': 'up',
          }),
        );
      }
      return KeyEventResult.handled;
    }
    if (!canSendInput || (ime && code != 4)) return KeyEventResult.ignored;
    if (code != null) {
      if (event is KeyRepeatEvent && !heldKeys.containsKey(code)) {
        return KeyEventResult.ignored;
      }
      heldKeys[code] = presentation.binding;
      unawaited(
        send(InteropCommand.sessionKey, {
          'keyCode': code,
          'action': event is KeyUpEvent ? 'up' : 'down',
        }),
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.character?.isNotEmpty == true) {
      unawaited(send(InteropCommand.sessionText, {'text': event.character}));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void pressNavigationKey(int code) {
    if (!canSendInput) return;
    unawaited(
      send(InteropCommand.sessionKey, {'keyCode': code, 'action': 'down'}),
    );
    unawaited(
      send(InteropCommand.sessionKey, {'keyCode': code, 'action': 'up'}),
    );
  }

  Future<void> leave() async {
    if (presentation.exiting) return;
    releaseDeviceView();
    setState(() {
      presentation.leave();
    });
    final feedback = ScaffoldMessenger.maybeOf(context);
    final deviceLabel = deviceName(widget.device);
    final left = Completer<void>();
    final lock =
        widget.packageName == null &&
        view?.isCurrent == true &&
        presentation.controlAvailable &&
        !presentation.stateUnverified &&
        jsonObject(
              jsonObject(
                controller.snapshot().settings['deviceSettings'],
              )[value(widget.device, 'id')],
            )['lockOnClose'] ==
            true;
    final lastPhonePage = releasePhonePage?.call() == true;
    if (sessionId.isNotEmpty) {
      // Input release and pause stay ordered for this exact session. Leaving
      // local presentation must not wait for a remote acknowledgement.
      final releases = releaseInputs();
      final beforePause = lock && lastPhonePage
          ? releases.then((_) async {
              if (view?.ownsBinding != true ||
                  controller.hasPhoneControlPages(value(widget.device, 'id'))) {
                return;
              }
              try {
                await controller.execute(InteropCommand.sessionKey, {
                  'sessionId': sessionId,
                  'keyCode': 223,
                  'action': 'down',
                });
                await controller.execute(InteropCommand.sessionKey, {
                  'sessionId': sessionId,
                  'keyCode': 223,
                  'action': 'up',
                });
              } catch (failure) {
                unawaited(
                  left.future.then((_) {
                    if (feedback?.mounted == true) {
                      feedback!.showSnackBar(
                        glassSnackBar(
                          '已退出 $deviceLabel 的画面，锁屏尚未确认：${remoteFailure(failure)}。请在手机核对。',
                        ),
                      );
                    }
                  }),
                );
              }
            })
          : releases;
      final cleanup = view?.release(afterInput: beforePause);
      presentation.revokeControl();
      if (cleanup != null) {
        unawaited(
          cleanup.catchError((Object failure) async {
            await left.future;
            if (feedback?.mounted == true) {
              feedback!.showSnackBar(
                glassSnackBar(
                  '已退出 $deviceLabel 的画面，${lock && lastPhonePage ? '锁屏或暂停' : '暂停窗口'}尚未确认：${remoteFailure(failure)}。可在控制会话中核对。',
                ),
              );
            }
            return <String, dynamic>{};
          }),
        );
      }
    }
    // Let PopScope publish the local exit state before popping the route.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) closePage<void>(context);
    await WidgetsBinding.instance.endOfFrame;
    left.complete();
  }

  @override
  void dispose() {
    resizeTimer?.cancel();
    releasePhonePage?.call();
    if (!initialViewport.isCompleted) initialViewport.complete(Size.zero);
    releaseDeviceView();
    presentation.invalidateStart();
    final release = releaseInputs();
    final ownedView = view;
    if (!presentation.exiting && ownedView != null) {
      unawaited(
        ownedView
            .release(afterInput: release)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    sessionRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    eventSubscription?.cancel();
    text.removeListener(textChanged);
    inputFocus.removeListener(inputFocusChanged);
    inputFocus.dispose();
    keyboardFocus.dispose();
    text.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void observeViewport(Size size) {
    if (imeBlocksDisplaySizing) {
      resizeTimer?.cancel();
      return;
    }
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    displayViewport = size;
    if (!initialViewport.isCompleted) initialViewport.complete(size);
    if (!autoDisplay || sessionId.isEmpty || !canSendInput || resizingDisplay) {
      return;
    }
    final target = const RemoteDisplaySettings({'remoteAspectRatio': 'auto'})
        .dimensions(size);
    if (target == null || target == requestedDisplaySize) {
      resizeTimer?.cancel();
      return;
    }
    final binding = presentation.binding;
    // Frames can rebuild this layout faster than the debounce interval. Only
    // a changed target or binding restarts the pending adjustment.
    if (resizeTimer?.isActive == true &&
        scheduledDisplaySize == target &&
        scheduledDisplayBinding == binding) {
      return;
    }
    resizeTimer?.cancel();
    scheduledDisplaySize = target;
    scheduledDisplayBinding = binding;
    resizeTimer = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted ||
          !canSendInput ||
          binding != presentation.binding ||
          imeBlocksDisplaySizing) {
        return;
      }
      setState(() => resizingDisplay = true);
      try {
        await releaseInputs();
        if (!mounted ||
            !hasInputAuthority ||
            binding != presentation.binding ||
            imeBlocksDisplaySizing) {
          return;
        }
        requestedDisplaySize = target;
        await controller.execute(InteropCommand.sessionDisplay, {
          'sessionId': binding.$1,
          'displayWidth': target.width,
          'displayHeight': target.height,
        });
        if (mounted && binding == presentation.binding) {
          appliedDisplaySize = target;
        }
      } catch (failure) {
        if (mounted && binding == presentation.binding) {
          remoteMessenger.currentState?.showSnackBar(
            glassSnackBar('屏幕比例调整未确认：${remoteFailure(failure)}'),
          );
        }
      } finally {
        if (mounted) setState(() => resizingDisplay = false);
        if (mounted && displayViewport != null) {
          observeViewport(displayViewport!);
        }
      }
    });
  }

  void observeRemoteGeometry() {
    if (!autoDisplay || displayViewport == null) return;
    final width = int.tryParse('${presentation.session?['width']}');
    final height = int.tryParse('${presentation.session?['height']}');
    if (width == null || height == null || width <= 0 || height <= 0) return;
    final geometry = (width: width, height: height);
    if (geometry == lastRemoteGeometry) return;
    lastRemoteGeometry = geometry;
    final target = const RemoteDisplaySettings({'remoteAspectRatio': 'auto'})
        .dimensions(displayViewport!);
    if (target != null &&
        (width / height - target.width / target.height).abs() > .005) {
      // Physical device rotation changes natural-coordinate mapping even when
      // this host's viewport did not change. Reapply once for that geometry.
      requestedDisplaySize = null;
      observeViewport(displayViewport!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold removes the inherited bottom viewInset after resizing its body.
    // Read the route's original inset so an IME cannot redefine display size.
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible ||
        (waitingForIme &&
            imeRequestedWindowSize != MediaQuery.sizeOf(context))) {
      // A hardware keyboard need not produce an IME inset. A real host resize
      // still adapts; transient system bars in the same window never end this
      // wait merely because the IME took longer to appear.
      waitingForIme = false;
    }
    if (keyboardVisible || waitingForIme) resizeTimer?.cancel();
    final width = (num.tryParse('${presentation.session?['width']}') ?? 0)
        .toDouble();
    final height = (num.tryParse('${presentation.session?['height']}') ?? 0)
        .toDouble();
    final texture = int.tryParse('${presentation.session?['textureId']}');
    final valid = texture != null && width > 0 && height > 0;
    // The app messenger carries feedback between routes. A remote session has
    // its own scope so results from local pages cannot cover the phone screen.
    return Consumer(
      builder: (context, ref, _) {
        final showNavigationBar = ref.watch(
          appControllerProvider.select(
            (state) =>
                jsonObject(
                  jsonObject(state.settings['deviceSettings'])[value(
                    widget.device,
                    'id',
                  )],
                )['showNavigationBar'] !=
                false,
          ),
        );
        return ScaffoldMessenger(
          key: remoteMessenger,
          child: PopScope(
            canPop: presentation.exiting,
            onPopInvokedWithResult: (popped, _) {
              if (!popped) pressNavigationKey(4);
            },
            child: Focus(
              autofocus: true,
              focusNode: keyboardFocus,
              onKeyEvent: key,
              onFocusChange: (focused) {
                if (!focused) unawaited(releaseInputs());
              },
              child: Scaffold(
                backgroundColor: Colors.black,
                resizeToAvoidBottomInset: true,
                bottomNavigationBar: showNavigationBar
                    ? SafeArea(
                        top: false,
                        child: SizedBox(
                          height: DesignTokens.componentPageHeaderHeight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              GlassActionIcon(
                                tooltip: '返回',
                                onPressed: canSendInput
                                    ? () => pressNavigationKey(4)
                                    : null,
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                              ),
                              GlassActionIcon(
                                tooltip: '主屏幕',
                                onPressed: canSendInput
                                    ? () => pressNavigationKey(3)
                                    : null,
                                icon: const Icon(
                                  Icons.circle_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              GlassActionIcon(
                                tooltip: '最近任务',
                                onPressed: canSendInput
                                    ? () => pressNavigationKey(187)
                                    : null,
                                icon: const Icon(
                                  Icons.crop_square,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : null,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (!keyboardVisible && !waitingForIme) {
                              observeViewport(constraints.biggest);
                            }
                            return Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) => pointer(
                                event,
                                'down',
                                constraints.biggest,
                                Size(width, height),
                              ),
                              onPointerMove: (event) => pointer(
                                event,
                                'move',
                                constraints.biggest,
                                Size(width, height),
                              ),
                              onPointerUp: (event) => pointer(
                                event,
                                'up',
                                constraints.biggest,
                                Size(width, height),
                              ),
                              onPointerCancel: (event) => pointer(
                                event,
                                'cancel',
                                constraints.biggest,
                                Size(width, height),
                              ),
                              child: valid
                                  ? Center(
                                      child: AspectRatio(
                                        aspectRatio: width / height,
                                        child: Texture(textureId: texture),
                                      ),
                                    )
                                  : const SizedBox.expand(),
                            );
                          },
                        ),
                      ),
                      if (presentation.connecting)
                        const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      if (presentation.error != null || presentation.paused)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final media = MediaQuery.of(context);
                            final exit = ExitHandle.initialBoundsFor(
                              constraints.biggest,
                              media,
                            );
                            final belowExit =
                                exit.bottom + DesignTokens.spacingSm;
                            final bottom = math.max(
                              DesignTokens.spacingXl,
                              media.padding.bottom,
                            );
                            final roomBelow =
                                constraints.maxHeight - belowExit - bottom;
                            // A short landscape viewport can use the space beside
                            // the exit control; taller layouts reserve its top band.
                            final below =
                                roomBelow >=
                                DesignTokens.componentRowHeight * 2;
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                below
                                    ? math.max(
                                        DesignTokens.spacingXl,
                                        media.padding.left,
                                      )
                                    : exit.right + DesignTokens.spacingSm,
                                below
                                    ? belowExit
                                    : math.max(
                                        DesignTokens.spacingXl,
                                        media.padding.top,
                                      ),
                                math.max(
                                  DesignTokens.spacingXl,
                                  media.padding.right,
                                ),
                                bottom,
                              ),
                              child: Center(
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'remote-recovery-content',
                                  ),
                                  child: Glass(
                                    radius: DesignTokens.roundedLg,
                                    padding: const EdgeInsets.all(
                                      DesignTokens.spacingLg,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 360,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            presentation.paused
                                                ? LucideIcons.pause
                                                : LucideIcons.monitorOff,
                                            size: DesignTokens
                                                .componentIconLargeSize,
                                          ),
                                          const SizedBox(
                                            height: DesignTokens.spacingMd,
                                          ),
                                          Text(
                                            presentation.sessionEnded
                                                ? '控制会话已结束'
                                                : presentation.appLaunchUnknown
                                                ? '应用打开结果待核对'
                                                : presentation.stateUnverified
                                                ? '正在核验会话状态'
                                                : presentation.errorCode ==
                                                      'device_asleep'
                                                ? '手机处于休眠状态'
                                                : presentation.paused
                                                ? '画面已暂停'
                                                : '暂时无法打开实时画面',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                          ),
                                          const SizedBox(
                                            height: DesignTokens.spacingXs,
                                          ),
                                          Text(
                                            presentation.error ?? '等待连接恢复后的首帧。',
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(
                                            height: DesignTokens.spacingMd,
                                          ),
                                          if (presentation.errorCode ==
                                              'resource_busy')
                                            FilledButton(
                                              onPressed: () =>
                                                  DeviceActivitiesRoute(
                                                    deviceId: value(
                                                      widget.device,
                                                      'id',
                                                    ),
                                                  ).push<void>(context),
                                              child: const Text('管理当前活动'),
                                            ),
                                          if (presentation.errorCode ==
                                              'device_asleep')
                                            FilledButton(
                                              onPressed: presentation.connecting
                                                  ? null
                                                  : wakeAndStart,
                                              child: const Text('唤醒手机'),
                                            ),
                                          if (widget.packageName != null &&
                                              presentation.error != null &&
                                              !presentation.appLaunchUnknown &&
                                              !presentation.stateUnverified)
                                            FilledButton(
                                              onPressed: presentation.connecting
                                                  ? null
                                                  : continueOnPhoneScreen,
                                              child: const Text('在手机屏幕继续'),
                                            ),
                                          if (presentation.appLaunchUnknown)
                                            FilledButton(
                                              onPressed: presentation.connecting
                                                  ? null
                                                  : closeUnknownAppLaunch,
                                              child: const Text('关闭本次打开记录'),
                                            ),
                                          OutlinedButton(
                                            onPressed: presentation.connecting
                                                ? null
                                                : presentation.appLaunchUnknown
                                                ? checkAppLaunch
                                                : (presentation.reconcileOnly
                                                      ? reconcileState
                                                      : start),
                                            child: Text(
                                              presentation.appLaunchUnknown
                                                  ? '只读检查'
                                                  : presentation.appLaunchClosed
                                                  ? '重新打开'
                                                  : '重新检查',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (ime)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          width: 1,
                          height: 1,
                          child: TextField(
                            focusNode: inputFocus,
                            controller: text,
                            autofocus: true,
                            obscureText: sensitive,
                            enableSuggestions: !sensitive,
                            autocorrect: !sensitive,
                            enableInteractiveSelection: !sensitive,
                            onSubmitted: (_) {
                              if (!canSendInput) return;
                              unawaited(
                                send(InteropCommand.sessionKey, {
                                  'keyCode': 66,
                                  'action': 'down',
                                }),
                              );
                              unawaited(
                                send(InteropCommand.sessionKey, {
                                  'keyCode': 66,
                                  'action': 'up',
                                }),
                              );
                            },
                          ),
                        ),
                      ExitHandle(
                        onExit: leave,
                        deviceLabel: deviceName(widget.device),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
