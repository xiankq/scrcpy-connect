import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/services/session_views.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show confirm;
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/remote_input.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Json? session;
  String? error;
  String? errorCode;
  bool connecting = true;
  bool paused = false;
  bool ime = false;
  bool sensitive = false;
  bool exiting = false;
  final inputFocus = FocusNode();
  final keyboardFocus = FocusNode();
  static const inputSentinel = '\u200B';
  final text = TextEditingController(text: inputSentinel);
  final activePointers = <int>{};
  final pointerPositions = <int, Json>{};
  final heldKeys = <int, (String, int)>{};
  final detachedCleanupBindings = <(String, int)>{};
  bool controlAvailable = false;
  int bindingGeneration = 0;
  int startAttempt = 0;
  bool lifecyclePaused = false;
  bool adjustmentShown = false;
  bool initialActionApplied = false;
  bool appLaunchUnknown = false;
  bool appLaunchClosed = false;
  SessionView? view;
  ModalRoute<dynamic>? observedRoute;
  bool covered = false;
  bool presentationVisible = true;
  bool awaitingResume = false;
  int visibilityEpoch = 0;
  bool stateUnverified = false;
  bool sessionEnded = false;
  bool reconcileOnly = false;
  int stateEpoch = 0;
  int? reconciledSequence;
  final remoteMessenger = GlobalKey<ScaffoldMessengerState>();

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
  bool get canSendInput =>
      acceptsInput &&
      controlAvailable &&
      !paused &&
      !connecting &&
      !exiting &&
      error == null &&
      view?.isCurrent == true &&
      !covered &&
      presentationVisible &&
      !awaitingResume &&
      !stateUnverified &&
      !appLaunchUnknown &&
      sessionId.isNotEmpty;

  Future<void> releaseInputs() {
    var completion = releasePointers();
    final keys = Map<int, (String, int)>.from(heldKeys);
    heldKeys.clear();
    if (!controlAvailable) return completion;
    for (final entry in keys.entries) {
      if (entry.value.$1 != sessionId || entry.value.$2 != bindingGeneration) {
        continue;
      }
      completion = send('session.key', {
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
    if (!controlAvailable) {
      return reconcileOnly ? inputQueue : Future<void>.value();
    }
    // A physical key-up can already be queued after its held entry was
    // removed. Flush live input before stopping or replacing this session.
    Future<void> completion = inputQueue;
    for (final params in releases) {
      completion = send('session.touch', {
        ...params,
        'action': 'cancel',
        'pressure': 0,
      });
    }
    return completion;
  }

  String previousText = inputSentinel;
  StreamSubscription<Json>? eventSubscription;
  Future<void> inputQueue = Future<void>.value();
  AppController get controller => widget.controller;
  String get sessionId =>
      value(session ?? {}, 'sessionId', value(session ?? {}, 'id'));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    eventSubscription = controller.eventStream().listen(onEvent);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (controller.snapshot().reconciliationPending) {
      session = widget.existingSession;
      markStateUnknown();
    } else {
      unawaited(start());
    }
  }

  Future<void> start() async {
    if (appLaunchUnknown) {
      await checkAppLaunch();
      return;
    }
    if (reconcileOnly || controller.snapshot().reconciliationPending) {
      await reconcileState();
      return;
    }
    final attempt = ++startAttempt;
    final recoveryEpoch = stateEpoch;
    trace(
      'start.begin lifecycle=${WidgetsBinding.instance.lifecycleState?.name}',
    );
    setState(() {
      connecting = true;
      error = null;
      errorCode = null;
    });
    var submittedAppStart = false;
    try {
      await releaseInputs();
      if (!mounted || exiting || attempt != startAttempt) return;
      controlAvailable = false;
      bindingGeneration++;
      Json? retained = widget.existingSession;
      if (retained == null) {
        final listed = objects(
          (await controller.request('session.list', {
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
      if (!mounted || exiting || attempt != startAttempt) return;
      if (retained?['launchOutcome'] == 'unknown') {
        showUnknownAppLaunch(retained!);
        return;
      }
      submittedAppStart = retained == null && widget.packageName != null;
      final result =
          retained ??
          await controller.request('session.start', {
            'deviceId': widget.device['id'],
            if (widget.packageName != null) 'packageName': widget.packageName,
          });
      if (!mounted || exiting || attempt != startAttempt) {
        if (mounted && !exiting && recoveryEpoch != stateEpoch) {
          // The launch was already submitted. Its late result is an identity
          // to verify, never a reason to launch or stop the task again.
          if (sessionId.isEmpty) {
            setState(() {
              session = {...result}..remove('textureId');
              stateUnverified = true;
              connecting = false;
              error = '会话结果尚待核验，请重新检查。';
            });
          }
          return;
        }
        if (retained == null) {
          final staleId = value(result, 'sessionId', value(result, 'id'));
          if (staleId.isNotEmpty && staleId != sessionId) {
            try {
              await controller.request('session.stop', {
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
        session = result;
        controlAvailable = sessionId.isNotEmpty && result['textureId'] != null;
        presentationVisible = true;
        awaitingResume = false;
        lifecyclePaused = false;
        connecting = retained != null && result['textureId'] != null;
        paused = result['status'] == 'paused';
        if (widget.requestKeyboard && result['textureId'] != null) ime = true;
        if (result['textureId'] == null) {
          if (submittedAppStart) appLaunchUnknown = true;
          error = value(result, 'reason', '尚未获得设备的实时画面。请检查设备连接和视频能力。');
        }
      });
      if (sessionId.isEmpty || result['textureId'] == null) return;
      view = controller.claimSessionView(
        sessionId,
        visible:
            result['status'] != 'paused' && result['capturePaused'] != true,
      );
      if (retained == null) {
        focusVisibleDevice();
      }
      if (retained != null) {
        await resumeView();
        if (!mounted || exiting || attempt != startAttempt) return;
      }
      if (covered) await pauseView();
      await applyPendingInitialAction();

      trace('start.bound paused=$paused');
      // The bridge returns this texture only after actual decoded pixels have
      // been read. Earlier output events can precede this page binding.
      if (result['textureId'] != null) showResourceAdjustment();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        didChangeAppLifecycleState(lifecycle);
      }
    } catch (e) {
      if (mounted && !exiting && attempt == startAttempt) {
        setState(() {
          connecting = false;
          error = remoteFailure(e);
          errorCode = remoteFailureCode(e);
          // Only explicit pre-submission rejections establish that retrying is
          // safe. Transport, encoder and renderer failures may follow START_APP.
          final details = e is RequestFailure
              ? jsonObject(e.details)
              : <String, dynamic>{};
          if (submittedAppStart &&
              details['launchOutcome'] != 'not_submitted' &&
              !const {
                'invalid_argument',
                'unsupported',
                'resource_busy',
                'device_asleep',
                'server_integrity',
                'encoder_unavailable',
                'decoder_unavailable',
                'state_unverified',
                'authorization_required',
              }.contains(errorCode)) {
            appLaunchUnknown = true;
            if (details['sessionId'] is String) session = details;
          }
        });
      }
    }
  }

  Future<void> applyPendingInitialAction() async {
    final action = widget.initialAction;
    if (initialActionApplied || action == null || !canSendInput) return;
    // Consume the intent before submitting any side effect. A missing receipt
    // leaves an unknown outcome and must never turn a resume into a replay.
    initialActionApplied = true;
    switch (action.tool) {
      case RemoteTool.rotate:
        await send('session.rotate', {});
      case RemoteTool.screen:
        await send('session.screen', {'mode': action.value});
      case RemoteTool.text:
        await send('session.text', {'text': action.value});
      case RemoteTool.launchApp:
        await send('session.launch', {
          'deviceId': widget.device['id'],
          'packageName': action.value,
        });
      case RemoteTool.key:
        final code = action.value! as int;
        heldKeys[code] = (sessionId, bindingGeneration);
        try {
          await send('session.key', {'keyCode': code, 'action': 'down'});
        } finally {
          heldKeys.remove(code);
          await send('session.key', {'keyCode': code, 'action': 'up'});
        }
    }
  }

  void showUnknownAppLaunch(Json record) {
    setState(() {
      session = {...record}..remove('textureId');
      appLaunchUnknown = true;
      stateUnverified = false;
      sessionEnded = false;
      connecting = false;
      controlAvailable = false;
      errorCode = 'app_launch_unknown';
      error = '应用打开请求的结果未知，应用可能已打开或迁移。请在手机核对；检查不会再次打开应用。';
    });
  }

  void detachForUnknownAppLaunch(Json record) {
    // Only this exact outgoing binding may drain cleanup after the page adopts
    // the operation record. New input still needs the current live binding.
    final outgoing = (sessionId, bindingGeneration);
    detachedCleanupBindings.add(outgoing);
    final releases = releaseInputs().whenComplete(() {
      detachedCleanupBindings.remove(outgoing);
    });
    final owned = view;
    view = null;
    visibilityEpoch++;
    bindingGeneration++;
    controlAvailable = false;
    presentationVisible = false;
    awaitingResume = false;
    paused = true;
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
    setState(() => connecting = true);
    try {
      final listed = objects(
        (await controller.request('session.list', {
          'deviceId': widget.device['id'],
        }))['sessions'],
      );
      if (!mounted || exiting) return;
      final record = listed
          .where(
            (item) => sessionId.isNotEmpty
                ? value(item, 'sessionId', value(item, 'id')) == sessionId
                : item['deviceId'] == widget.device['id'] &&
                      item['packageName'] == widget.packageName,
          )
          .firstOrNull;
      showUnknownAppLaunch(record ?? session ?? {});
    } catch (failure) {
      if (mounted && !exiting) {
        setState(() {
          connecting = false;
          error = remoteFailure(failure);
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
    setState(() => connecting = true);
    try {
      if (sessionId.isNotEmpty) {
        await controller.request('session.stop', {
          'sessionId': sessionId,
          'keepTask': true,
        });
      }
      if (!mounted || exiting) return;
      setState(() {
        session = null;
        appLaunchUnknown = false;
        appLaunchClosed = true;
        stateUnverified = false;
        sessionEnded = false;
        reconcileOnly = false;
        paused = false;
        connecting = false;
        if (widget.initialAction?.tool == RemoteTool.launchApp) {
          initialActionApplied = false;
        }
        errorCode = null;
        error = '本次打开记录已关闭，手机上的应用任务已保留。可明确选择重新打开。';
      });
    } catch (failure) {
      if (mounted && !exiting) {
        setState(() {
          connecting = false;
          error = remoteFailure(failure);
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
    setState(() => connecting = true);
    try {
      await controller.request('devices.wake', {
        'deviceId': widget.device['id'],
      });
      if (mounted) await start();
    } catch (failure) {
      if (mounted) {
        setState(() {
          connecting = false;
          error = remoteFailure(failure);
          errorCode = remoteFailureCode(failure);
        });
      }
    }
  }

  Future<void> continueOnPhoneScreen() async {
    final package = widget.packageName;
    if (package == null ||
        appLaunchUnknown ||
        stateUnverified ||
        !await confirm(
          context,
          '在手机屏幕继续？',
          '将在手机主屏打开此应用并接续真实任务，可能改变手机当前的前台应用。已打开的独立窗口可在窗口列表管理。',
          action: '继续打开',
        ) ||
        !mounted ||
        appLaunchUnknown ||
        stateUnverified) {
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
    if (event['type'] == 'state.resync') {
      markStateUnknown();
      return;
    }
    if (event['type'] == 'state.resync.failed') {
      markStateUnknown(value(data, 'reason', '状态检查未完成，请重试。'));
      return;
    }
    if (event['type'] == 'state.resynced') {
      applyReconciledState(data);
      return;
    }
    if (appLaunchUnknown ||
        stateUnverified ||
        (reconcileOnly && view?.isCurrent != true)) {
      return;
    }
    if (value(event, 'type').startsWith('session.')) {
      trace(
        'event type=${event['type']} status=${value(data, 'status')} bound=${sessionId.isNotEmpty} sessionMatches=${data['sessionId'] == null || data['sessionId'] == sessionId} deviceMatches=${event['deviceId'] == null || event['deviceId'] == widget.device['id']} hasTexture=${data['textureId'] != null} pausedBefore=$paused',
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
        final next = {...?session, ...data};
        if (!paused &&
            error == null &&
            next['width'] == session?['width'] &&
            next['height'] == session?['height'] &&
            next['textureId'] == session?['textureId']) {
          return;
        }
        setState(() {
          session = next;
          if (next['textureId'] != null &&
              presentationVisible &&
              !awaitingResume &&
              !covered) {
            paused = false;
            error = null;
          }
        });
        trace(
          'frame.applied paused=$paused hasTexture=${session?['textureId'] != null}',
        );
      case 'session.updated':
        setState(() {
          session = {...?session, ...data};
          if (data['status'] == 'streaming' && data['connected'] != false) {
            controlAvailable = true;
          }
          if ([
                'connecting',
                'reconnecting',
                'stopped',
              ].contains(data['status']) ||
              data['connected'] == false) {
            controlAvailable = false;
          }
          if ([
                'paused',
                'connecting',
                'reconnecting',
                'stopped',
              ].contains(data['status']) ||
              data['connected'] == false) {
            paused = true;
            unawaited(releaseInputs());
          }
        });
        trace('updated.applied paused=$paused');
      case 'session.disconnected':
      case 'session.failed':
        // A completed old resume is no longer evidence for this binding.
        // Hide presentation intent too: its separately emitted frame receipt
        // must not clear the terminal error after the Future is invalidated.
        visibilityEpoch++;
        bindingGeneration++;
        presentationVisible = false;
        awaitingResume = false;
        controlAvailable = false;
        unawaited(releaseInputs());
        setState(() {
          connecting = false;
          paused = true;
          error = value(data, 'reason', '连接已中断，当前画面已暂停。恢复首帧后才能继续操作。');
        });
      case 'session.ime':
        setState(() {
          ime = data['visible'] == true;
          sensitive = data['sensitive'] == true;
        });
        if (ime) {
          inputFocus.requestFocus();
        } else {
          inputFocus.unfocus();
        }
    }
  }

  void markStateUnknown([String? reason]) {
    trace(
      'reconcile.unknown reason=$reason session=$sessionId visibility=$visibilityEpoch',
    );
    stateEpoch++;
    visibilityEpoch++;
    startAttempt++;
    // Freeze new input first, then drain only releases against this exact
    // binding. A UUID is never reused for a replacement control session.
    stateUnverified = true;
    unawaited(releaseInputs());
    bindingGeneration++;
    controlAvailable = false;
    setState(() {
      stateUnverified = true;
      sessionEnded = false;
      reconcileOnly = true;
      initialActionApplied = true;
      connecting = false;
      paused = true;
      awaitingResume = false;
      error = reason ?? '正在重新核对活动状态，完成前暂停操作。';
      errorCode = null;
    });
  }

  void applyReconciledState(Json snapshot) {
    final sequence = snapshot['sequence'];
    trace(
      'reconcile.snapshot sequence=$sequence session=$sessionId unverified=$stateUnverified covered=$covered lifecyclePaused=$lifecyclePaused acceptsInput=$acceptsInput',
    );
    if (!stateUnverified && sequence is int && sequence == reconciledSequence) {
      return;
    }
    reconciledSequence = sequence is int ? sequence : null;
    reconcileOnly = true;
    final observed = objects(snapshot['sessions']);
    final unknownApp = widget.packageName == null
        ? null
        : observed
              .where(
                (item) =>
                    item['deviceId'] == widget.device['id'] &&
                    item['packageName'] == widget.packageName &&
                    item['launchOutcome'] == 'unknown',
              )
              .firstOrNull;
    if (unknownApp != null) {
      // A page opened during recovery may not have a session ID yet. The
      // submitted app intent still belongs to this device/package and blocks
      // opening the same task on another display until explicitly resolved.
      visibilityEpoch++;
      showUnknownAppLaunch(unknownApp);
      return;
    }
    final existing = observed
        .where(
          (item) =>
              value(item, 'sessionId', value(item, 'id')) == sessionId &&
              sessionId.isNotEmpty,
        )
        .firstOrNull;
    visibilityEpoch++;
    setState(() {
      connecting = false;
      paused = true;
      awaitingResume = false;
      controlAvailable = false;
      if (existing == null ||
          ['stopped', 'failed', 'error'].contains(existing['status'])) {
        session = {...?session}..remove('textureId');
        stateUnverified = true;
        sessionEnded = true;
        error = '原会话已结束或无法核验。请检查当前活动，不会自动创建新窗口。';
      } else {
        session = existing;
        stateUnverified = false;
        sessionEnded = false;
        error = null;
      }
    });
    if (stateUnverified) return;
    if (!covered && acceptsInput && !lifecyclePaused) {
      unawaited(resumeView());
    } else {
      unawaited(pauseView());
    }
  }

  Future<void> reconcileState() async {
    markStateUnknown();
    final epoch = stateEpoch;
    try {
      // The Bridge publishes state.resynced only after its full read barrier.
      // A command receipt alone must never unlock this surface.
      await controller.request('state.reconcile');
    } catch (failure) {
      if (mounted && !exiting && epoch == stateEpoch) {
        setState(() => error = remoteFailure(failure));
      }
    }
  }

  void showResourceAdjustment() {
    final message = value(session ?? {}, 'resourceAdjustment');
    if (adjustmentShown || message.isEmpty || session?['textureId'] is! int) {
      return;
    }
    adjustmentShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !exiting) {
        remoteMessenger.currentState?.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
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
    covered = true;
    unawaited(pauseView());
  }

  @override
  void didPopNext() {
    covered = false;
    if (acceptsInput) unawaited(resumeView());
  }

  Future<void> pauseView() async {
    if (exiting || appLaunchUnknown) return;
    final owned = view;
    if (owned == null || !owned.isCurrent) return;
    final epoch = ++visibilityEpoch;
    presentationVisible = false;
    final releases = releaseInputs();
    if (mounted) setState(() => paused = true);
    try {
      await owned.pause(afterInput: releases);
    } catch (failure) {
      if (mounted && !exiting && epoch == visibilityEpoch) {
        setState(() => error = remoteFailure(failure));
      }
    }
  }

  void focusVisibleDevice() {
    // A retained page can finish starting or resuming after another device
    // becomes visible. Only the current route and session owner may set focus.
    if (!mounted ||
        exiting ||
        covered ||
        !acceptsInput ||
        stateUnverified ||
        sessionEnded ||
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
    if (appLaunchUnknown ||
        stateUnverified ||
        sessionId.isEmpty ||
        covered ||
        exiting ||
        !acceptsInput) {
      return;
    }
    var owned = view;
    if (owned == null || !owned.isCurrent) {
      owned = controller.claimSessionView(sessionId, visible: false);
      view = owned;
    }
    focusVisibleDevice();
    final epoch = ++visibilityEpoch;
    trace('resume.begin epoch=$epoch session=$sessionId');
    presentationVisible = true;
    awaitingResume = true;
    setState(() => paused = true);
    try {
      final receipt = await owned.resume(afterInput: inputQueue);
      trace(
        'resume.receipt epoch=$epoch current=$visibilityEpoch owned=${owned.isCurrent} covered=$covered evidence=${receipt['evidence']}',
      );
      if (!mounted ||
          exiting ||
          !owned.isCurrent ||
          covered ||
          epoch != visibilityEpoch) {
        return;
      }
      if (receipt['firstFrameDecoded'] != true ||
          receipt['evidence'] != 'mdk.snapshot') {
        throw const RequestFailure('renderer_not_ready', '尚未确认恢复后的画面，请重新检查。');
      }
      setState(() {
        session = {...?session, ...receipt};
        paused = false;
        awaitingResume = false;
        connecting = false;
        controlAvailable = session?['textureId'] != null;
        error = null;
      });
      await applyPendingInitialAction();
    } catch (failure) {
      trace(
        'resume.failed epoch=$epoch current=$visibilityEpoch reason=$failure',
      );
      if (mounted && !exiting && epoch == visibilityEpoch) {
        setState(() {
          connecting = false;
          error = remoteFailure(failure);
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(releaseInputs());
    if (state == AppLifecycleState.inactive || sessionId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      if (!lifecyclePaused) return;
      lifecyclePaused = false;
      if (!covered) unawaited(resumeView());
    } else {
      if (lifecyclePaused) return;
      lifecyclePaused = true;
      unawaited(pauseView());
    }
  }

  Future<void> send(String command, Json params) async {
    // Queue entries keep the binding that accepted them. A late request or
    // release must never inherit a replacement session's identity.
    final id = sessionId;
    final generation = bindingGeneration;
    final captured = {'sessionId': id, ...params};
    final cleanup =
        (command == 'session.key' && params['action'] == 'up') ||
        (command == 'session.touch' &&
            ['up', 'cancel'].contains(params['action']));
    inputQueue = inputQueue.then((_) async {
      final detachedCleanup =
          cleanup && detachedCleanupBindings.contains((id, generation));
      if ((!cleanup && !controlAvailable) ||
          id.isEmpty ||
          (id != sessionId && !detachedCleanup) ||
          (!cleanup && generation != bindingGeneration)) {
        return;
      }
      final newInput =
          command == 'session.text' ||
          (command == 'session.key' && params['action'] == 'down') ||
          (command == 'session.touch' &&
              ['down', 'move'].contains(params['action']));
      if (newInput && !canSendInput) return;
      await sendNow(command, captured, generation);
    });
    return inputQueue;
  }

  Future<void> sendNow(String command, Json params, int generation) async {
    trace('request.begin command=$command');
    try {
      await controller.request(command, params);
      trace('request.complete command=$command');
    } catch (e) {
      trace('request.failed command=$command kind=${e.runtimeType}');
      if (mounted && !exiting && params['sessionId'] == sessionId) {
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
        if (generation != bindingGeneration) return;
        if ([
          'not_found',
          'disconnected',
          'not_connected',
          'session_required',
        ].contains(remoteFailureCode(e))) {
          controlAvailable = false;
        }
        unawaited(releaseInputs());
        setState(() {
          error = remoteFailure(e);
          errorCode = remoteFailureCode(e);
          paused = true;
        });
      }
    }
  }

  void pointer(PointerEvent event, String action, Size viewport, Size source) {
    if (!canSendInput) {
      return;
    }
    var point = sourcePoint(event.localPosition, viewport, source);
    if (action == 'down') {
      if (point == null) return;
      activePointers.add(event.pointer);
    }
    if (!activePointers.contains(event.pointer)) return;
    // A pointer that began inside the source remains captured at its boundary.
    point ??= sourcePoint(event.localPosition, viewport, source, clamp: true)!;
    final params = <String, dynamic>{
      'action': action,
      'pointerId': event.pointer,
      'x': point.dx.round(),
      'y': point.dy.round(),
      'pressure': event.pressure,
      'screenWidth': source.width.round(),
      'screenHeight': source.height.round(),
    };
    if (action == 'down' || action == 'move') {
      pointerPositions[event.pointer] = params;
    }
    unawaited(send('session.touch', params));
    if (action == 'up' || action == 'cancel') {
      activePointers.remove(event.pointer);
      pointerPositions.remove(event.pointer);
    }
  }

  void textChanged(String next) {
    if (!canSendInput) {
      previousText = inputSentinel;
      text.value = const TextEditingValue(
        text: inputSentinel,
        selection: TextSelection.collapsed(offset: 1),
      );
      return;
    }
    // Only send committed IME text; pinyin/candidate composition remains local.
    if (text.value.composing.isValid && !text.value.composing.isCollapsed) {
      return;
    }
    final before = previousText.characters.toList();
    final after = next.characters.toList();
    var common = 0;
    while (common < before.length &&
        common < after.length &&
        before[common] == after[common]) {
      common++;
    }
    for (var i = common; i < before.length; i++) {
      unawaited(send('session.key', {'keyCode': 67, 'action': 'down'}));
      unawaited(send('session.key', {'keyCode': 67, 'action': 'up'}));
    }
    final added = after.skip(common).join().replaceAll(inputSentinel, '');
    if (added.isNotEmpty) unawaited(send('session.text', {'text': added}));
    previousText = next;
    // Keep one invisible local character so IME backspace can still delete
    // pre-existing remote text after the local insertion buffer is empty.
    if (next.isEmpty) {
      previousText = inputSentinel;
      text.value = const TextEditingValue(
        text: inputSentinel,
        selection: TextSelection.collapsed(offset: 1),
      );
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
      if (held.$1 == sessionId &&
          held.$2 == bindingGeneration &&
          controlAvailable) {
        unawaited(
          send('session.key', {
            'sessionId': held.$1,
            'keyCode': code,
            'action': 'up',
          }),
        );
      }
      return KeyEventResult.handled;
    }
    if (!canSendInput || ime) return KeyEventResult.ignored;
    if (code != null) {
      if (event is KeyRepeatEvent && !heldKeys.containsKey(code)) {
        return KeyEventResult.ignored;
      }
      heldKeys[code] = (sessionId, bindingGeneration);
      unawaited(
        send('session.key', {
          'keyCode': code,
          'action': event is KeyUpEvent ? 'up' : 'down',
        }),
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.character?.isNotEmpty == true) {
      unawaited(send('session.text', {'text': event.character}));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> leave() async {
    if (exiting) return;
    setState(() {
      exiting = true;
    });
    startAttempt++;
    final feedback = ScaffoldMessenger.maybeOf(context);
    final deviceLabel = deviceName(widget.device);
    final left = Completer<void>();
    if (sessionId.isNotEmpty) {
      // Input release and pause stay ordered for this exact session. Leaving
      // local presentation must not wait for a remote acknowledgement.
      final cleanup = view?.release(afterInput: releaseInputs());
      controlAvailable = false;
      if (cleanup != null) {
        unawaited(
          cleanup.catchError((Object failure) async {
            await left.future;
            if (feedback?.mounted == true) {
              feedback!.showSnackBar(
                SnackBar(
                  content: Text(
                    '已退出 $deviceLabel 的画面，暂停窗口尚未确认：${remoteFailure(failure)}。可在控制会话中核对。',
                  ),
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
    startAttempt++;
    final release = releaseInputs();
    final ownedView = view;
    if (!exiting && ownedView != null) {
      unawaited(
        ownedView
            .release(afterInput: release)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    sessionRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    eventSubscription?.cancel();
    inputFocus.dispose();
    keyboardFocus.dispose();
    text.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (num.tryParse('${session?['width']}') ?? 0).toDouble();
    final height = (num.tryParse('${session?['height']}') ?? 0).toDouble();
    final texture = int.tryParse('${session?['textureId']}');
    final valid = texture != null && width > 0 && height > 0;
    // The app messenger carries feedback between routes. A remote session has
    // its own scope so results from local pages cannot cover the phone screen.
    return ScaffoldMessenger(
      key: remoteMessenger,
      child: PopScope(
        canPop: exiting,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) unawaited(leave());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: Focus(
            autofocus: true,
            focusNode: keyboardFocus,
            onKeyEvent: key,
            onFocusChange: (focused) {
              if (!focused) unawaited(releaseInputs());
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Listener(
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
                    ),
                  ),
                ),
                if (connecting)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                if (error != null || paused)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Glass(
                        solid: true,
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                paused
                                    ? LucideIcons.pause
                                    : LucideIcons.monitorOff,
                                size: 32,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                sessionEnded
                                    ? '控制会话已结束'
                                    : appLaunchUnknown
                                    ? '应用打开结果待核对'
                                    : stateUnverified
                                    ? '正在核验会话状态'
                                    : errorCode == 'device_asleep'
                                    ? '手机处于休眠状态'
                                    : paused
                                    ? '画面已暂停'
                                    : '暂时无法打开实时画面',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error ?? '等待连接恢复后的首帧。',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              if (errorCode == 'resource_busy')
                                FilledButton(
                                  onPressed: () =>
                                      ActivitiesRoute().push<void>(context),
                                  child: const Text('管理当前活动'),
                                ),
                              if (errorCode == 'device_asleep')
                                FilledButton(
                                  onPressed: connecting ? null : wakeAndStart,
                                  child: const Text('唤醒手机'),
                                ),
                              if (widget.packageName != null &&
                                  error != null &&
                                  !appLaunchUnknown &&
                                  !stateUnverified)
                                FilledButton(
                                  onPressed: connecting
                                      ? null
                                      : continueOnPhoneScreen,
                                  child: const Text('在手机屏幕继续'),
                                ),
                              if (appLaunchUnknown)
                                FilledButton(
                                  onPressed: connecting
                                      ? null
                                      : closeUnknownAppLaunch,
                                  child: const Text('关闭本次打开记录'),
                                ),
                              OutlinedButton(
                                onPressed: connecting
                                    ? null
                                    : appLaunchUnknown
                                    ? checkAppLaunch
                                    : (reconcileOnly ? reconcileState : start),
                                child: Text(
                                  appLaunchUnknown
                                      ? '只读检查'
                                      : appLaunchClosed
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
                      onChanged: textChanged,
                      onSubmitted: (_) {
                        if (!canSendInput) return;
                        unawaited(
                          send('session.key', {
                            'keyCode': 66,
                            'action': 'down',
                          }),
                        );
                        unawaited(
                          send('session.key', {'keyCode': 66, 'action': 'up'}),
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
    );
  }
}
