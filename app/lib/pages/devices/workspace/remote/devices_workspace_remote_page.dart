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
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

import 'remote_connection_recovery.dart';
import 'remote_input_queue.dart';
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
  RemoteBinding? keepActiveNoticeBinding;
  (String, String)? keepActiveErrorKey;
  String? pendingKeepActiveNotice;
  bool keepActiveNoticeScheduled = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? remoteNoticeTail;
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
  Timer? screenStateTimer;
  bool? screenOn, screenLocked;
  bool waking = false;
  bool converting = false;
  bool readingScreenState = false;
  Future<void>? newWindowWake;
  int screenStateGeneration = 0;

  Future<void> refreshScreenState() async {
    if (!mounted ||
        presentation.exiting ||
        !acceptsInput ||
        presentation.covered ||
        readingScreenState) {
      return;
    }
    readingScreenState = true;
    final generation = ++screenStateGeneration;
    final connection = controller
        .snapshot()
        .devices
        .where((d) => d['id'] == widget.device['id'])
        .firstOrNull?['connectionId'];
    try {
      final result = await controller.request('device.screen.state', {
        'deviceId': widget.device['id'],
        'connectionId': ?connection,
      });
      if (!mounted ||
          presentation.exiting ||
          generation != screenStateGeneration ||
          !acceptsInput ||
          presentation.covered) {
        return;
      }
      final currentConnection = controller
          .snapshot()
          .devices
          .where((d) => d['id'] == widget.device['id'])
          .firstOrNull?['connectionId'];
      if (connection != currentConnection ||
          result['deviceId'] != widget.device['id'] ||
          (connection != null && result['connectionId'] != connection)) {
        return;
      }
      setState(() {
        screenOn = result['screenOn'] is bool
            ? result['screenOn'] as bool
            : null;
        screenLocked = result['locked'] is bool
            ? result['locked'] as bool
            : null;
      });
    } catch (_) {
      if (mounted && generation == screenStateGeneration) {
        setState(() {
          screenOn = null;
          screenLocked = null;
        });
      }
    } finally {
      readingScreenState = false;
    }
  }

  Future<void> requestWake() async {
    Object? currentConnection() =>
        controller
            .snapshot()
            .devices
            .where((device) => device['id'] == widget.device['id'])
            .firstOrNull?['connectionId'] ??
        widget.device['connectionId'];
    final connection = currentConnection();
    await controller.execute(InteropCommand.devicesWake, {
      'deviceId': widget.device['id'],
      'connectionId': ?connection,
    });
    if (!mounted || presentation.exiting) return;
    if (connection != currentConnection()) {
      throw const RequestFailure('stale_connection', '点亮请求所属连接已变化，请核对当前画面。');
    }
  }

  Future<void> wakeScreen() async {
    if (waking || presentation.exiting) return;
    setState(() => waking = true);
    try {
      await requestWake();
      if (!mounted || presentation.exiting) return;
      // An explicit wake can resolve a failed startup wake without replaying
      // the failed request automatically on a later start retry.
      newWindowWake = Future<void>.value();
      await refreshScreenState();
      if (mounted && presentation.errorCode == 'device_asleep') await start();
    } catch (failure) {
      if (mounted) {
        showRemoteNotice('点亮屏幕尚未确认：${remoteFailure(failure)}');
      }
    } finally {
      if (mounted) setState(() => waking = false);
    }
  }

  Future<void> screenshot() async {
    final owned = view;
    final id = sessionId;
    if (owned?.isCurrent != true || id.isEmpty) return;
    try {
      final result = await controller.execute(
        InteropCommand.sessionScreenshot,
        {'sessionId': id},
      );
      if (!mounted || view != owned || sessionId != id) return;
      final path = value(result, 'localPath');
      if (path.isEmpty) {
        throw const RequestFailure('capture_failed', '没有收到截图保存位置。');
      }
      showRemoteNotice('截图已保存：$path');
    } catch (failure) {
      if (mounted) {
        showRemoteNotice('截图失败：${remoteFailure(failure)}');
      }
    }
  }

  Future<void> convertToIndependent() async {
    if (converting || widget.packageName != null || !canSendInput) return;
    final binding = presentation.binding;
    final owned = view;
    final id = value(widget.device, 'id');
    String connectionId() => value(
      controller.snapshot().devices.where((d) => d['id'] == id).firstOrNull ??
          widget.device,
      'connectionId',
    );
    final connection = connectionId();
    if (connection.isEmpty) {
      showRemoteNotice('尚未确认当前设备连接。');
      return;
    }
    setState(() => converting = true);
    bool current() =>
        mounted &&
        !presentation.exiting &&
        canSendInput &&
        presentation.binding == binding &&
        view == owned &&
        connectionId() == connection;
    try {
      final foreground = await controller.request('apps.foreground', {
        'deviceId': id,
        'connectionId': connection,
      });
      if (!current()) return;
      final package = value(foreground, 'packageName');
      if (foreground['deviceId'] != id ||
          foreground['connectionId'] != connection ||
          foreground['source'] != 'resumedActivity' ||
          package.isEmpty) {
        throw const RequestFailure('foreground_unavailable', '无法确认手机当前前台应用。');
      }
      final running = await controller.request('apps.list', {
        'deviceId': id,
        'filter': 'running',
      });
      if (!current()) return;
      if (running['deviceId'] != id ||
          running['source'] != 'runningTasks' ||
          running['live'] != true ||
          (running['connectionId'] != null &&
              running['connectionId'] != connection) ||
          !objects(running['apps'])
              .any((app) => app['packageName'] == package)) {
        throw const RequestFailure(
          'foreground_unavailable',
          '当前前台内容没有可接续的应用任务。',
        );
      }
      final verified = await controller.request('apps.foreground', {
        'deviceId': id,
        'connectionId': connection,
      });
      if (!current()) return;
      if (verified['packageName'] != package ||
          verified['connectionId'] != connection ||
          verified['deviceId'] != id ||
          verified['source'] != 'resumedActivity') {
        throw const RequestFailure('foreground_unavailable', '手机前台应用已变化，请重试。');
      }
      await owned!.close(afterInput: releaseInputs());
      if (!mounted ||
          presentation.exiting ||
          presentation.binding != binding ||
          connectionId() != connection) {
        return;
      }
      presentation.detachBinding();
      RemoteAppRoute(
        deviceId: id,
        packageName: package,
        $extra: const RemoteLaunchIntent(),
      ).pushReplacement(context);
    } catch (failure) {
      if (mounted && !presentation.exiting) {
        showRemoteNotice('无法转为独立窗口：${remoteFailure(failure)}');
      }
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  void showKeyboard() {
    if (!canSendInput) return;
    setState(() => ime = true);
    requestImeFocus();
  }

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

  void showRemoteNotice(String message) {
    final notice = remoteMessenger.currentState?.showSnackBar(
      glassSnackBar(message),
    );
    if (notice == null) return;
    remoteNoticeTail = notice;
    unawaited(
      notice.closed.then((_) {
        if (!mounted) return;
        if (identical(remoteNoticeTail, notice)) remoteNoticeTail = null;
        showPendingKeepActiveNotice();
      }),
    );
  }

  void consumeKeepActiveNotice(Json receipt) {
    if (!receipt.containsKey('keepActiveError') || presentation.exiting) return;
    final binding = presentation.binding;
    if (keepActiveNoticeBinding != binding) {
      keepActiveNoticeBinding = binding;
      keepActiveErrorKey = null;
      pendingKeepActiveNotice = null;
    }
    if (receipt['keepActiveError'] == null) {
      keepActiveErrorKey = null;
      pendingKeepActiveNotice = null;
      return;
    }
    final error = jsonObject(receipt['keepActiveError']);
    final reason = value(error, 'reason', '保持唤醒服务未能确认。');
    final key = (value(error, 'code'), reason);
    if (keepActiveErrorKey == key) return;
    keepActiveErrorKey = key;
    pendingKeepActiveNotice = '保持唤醒尚未确认：$reason';
    showPendingKeepActiveNotice();
  }

  void showPendingKeepActiveNotice() {
    if (pendingKeepActiveNotice == null || keepActiveNoticeScheduled) return;
    keepActiveNoticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      keepActiveNoticeScheduled = false;
      if (!mounted || presentation.exiting) return;
      if (keepActiveNoticeBinding != presentation.binding) {
        pendingKeepActiveNotice = null;
        return;
      }
      if (!acceptsInput ||
          presentation.covered ||
          presentation.stateUnverified ||
          presentation.sessionEnded ||
          view?.isCurrent != true ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final messenger = remoteMessenger.currentState;
      final message = pendingKeepActiveNotice;
      // A queued SnackBar cannot be individually cancelled. Keep this fact in
      // page state until prior notices close, then recheck route and binding.
      if (messenger == null || message == null || remoteNoticeTail != null) {
        return;
      }
      pendingKeepActiveNotice = null;
      showRemoteNotice(message);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> releaseInputs({RemoteBinding? binding}) {
    final outgoing = binding ?? presentation.binding;
    resetTextInput();
    var completion = releasePointers(binding: binding);
    final keys = Map<int, RemoteBinding>.from(heldKeys);
    heldKeys.clear();
    if (!presentation.controlAvailable && binding == null) return completion;
    for (final entry in keys.entries) {
      if (entry.value != outgoing) {
        continue;
      }
      completion = send(InteropCommand.sessionKey, {
        'sessionId': entry.value.$1,
        'keyCode': entry.key,
        'action': 'up',
      }, binding: outgoing);
    }
    return completion;
  }

  Future<void> releasePointers({RemoteBinding? binding}) {
    final releases = pointerPositions.values.toList();
    activePointers.clear();
    pointerPositions.clear();
    if (!presentation.controlAvailable && binding == null) {
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
      }, binding: binding);
    }
    return completion;
  }

  String previousText = inputSentinel;
  bool resettingText = false;
  StreamSubscription<Json>? eventSubscription;
  late final RemoteInputQueue _inputQueue = RemoteInputQueue(
    dispatch: _dispatchInput,
    admits: _admitsInput,
  );
  Future<void> get inputQueue => _inputQueue.idle;
  AppController get controller => widget.controller;
  String get sessionId => presentation.sessionId;
  @override
  void initState() {
    super.initState();
    releaseDeviceView = controller.claimRemoteDeviceView(
      value(widget.device, 'id'),
    );
    screenStateTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshScreenState()),
    );
    unawaited(refreshScreenState());
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
      final viewport = displaySettings.mode == 'auto'
          ? await initialViewport.future
          : Size.zero;
      if (!mounted || !presentation.acceptsStart(attempt)) return;
      final dimensions = displaySettings.dimensions(viewport);
      if (retained == null &&
          !recoveringConnection &&
          displaySettings.values['wakeOnConnect'] == true) {
        // Consume this new-window intent before requesting input. A failed or
        // missing receipt cannot be replayed by a rebuild or generic retry.
        await (newWindowWake ??= requestWake());
        if (!mounted || !presentation.acceptsStart(attempt)) return;
      }
      submittedAppStart = retained == null && widget.packageName != null;
      final result =
          retained ??
          await controller.execute(InteropCommand.sessionStart, {
            'deviceId': widget.device['id'],
            if (widget.packageName != null) 'packageName': widget.packageName,
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
      releasePhonePage?.call();
      releasePhonePage = controller.claimPhoneControlPage(
        value(widget.device, 'id'),
        sessionId: sessionId,
      );
      view = controller.claimSessionView(
        sessionId,
        visible: result['status'] != 'paused',
      );
      consumeKeepActiveNotice(result);
      unawaited(refreshScreenState());
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
      newWindowWake = null;
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
    if (event['type'] == 'devices.changed' ||
        event['type'] == 'device.changed') {
      final updated = event['type'] == 'device.changed'
          ? data
          : objects(data['devices'])
                .where((d) => d['id'] == widget.device['id'])
                .firstOrNull;
      if (updated != null &&
          updated['id'] == widget.device['id'] &&
          updated['status'] != 'connected') {
        screenStateGeneration++;
        setState(() {
          screenOn = null;
          screenLocked = null;
        });
      }
    }
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
        if (!presentation.output(
          data,
          verified: event['type'] != 'session.frame',
        )) {
          return;
        }
        setState(() {});
        observeRemoteGeometry();
        trace(
          'frame.applied paused=${presentation.paused} hasTexture=${presentation.session?['textureId'] != null}',
        );
      case 'session.updated':
        final outgoing = presentation.binding;
        final current = presentation.session ?? {};
        final noticeIsCurrent =
            view?.isCurrent == true &&
            event['deviceId'] == widget.device['id'] &&
            (data['deviceId'] == null ||
                data['deviceId'] == widget.device['id']) &&
            data['sessionId'] == sessionId &&
            (current['captureGeneration'] == null ||
                data['captureGeneration'] != null) &&
            ((current['rendererGeneration'] ?? current['generation']) == null ||
                (data['rendererGeneration'] ?? data['generation']) != null) &&
            presentation.acceptsFailure(data);
        if (presentation.updateSession(data)) {
          unawaited(
            releaseInputs(
              binding: outgoing != presentation.binding ? outgoing : null,
            ),
          );
        }
        if (noticeIsCurrent) consumeKeepActiveNotice(data);
        setState(() {});
        trace('updated.applied paused=${presentation.paused}');
      case 'session.disconnected':
      case 'session.failed':
        if (!presentation.acceptsFailure(data)) return;
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
        showRemoteNotice(message);
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
    showPendingKeepActiveNotice();
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
      releasePhonePage?.call();
      releasePhonePage = null;
    }
    releasePhonePage ??= controller.claimPhoneControlPage(
      value(widget.device, 'id'),
      sessionId: sessionId,
    );
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
      showPendingKeepActiveNotice();
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
      showPendingKeepActiveNotice();
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

  Future<void> send(
    InteropCommand command,
    Json params, {
    RemoteBinding? binding,
  }) {
    // Queue entries keep the binding that accepted them. A late request or
    // release must never inherit a replacement session's identity.
    final outgoing = binding ?? presentation.binding;
    final captured = {'sessionId': outgoing.$1, ...params};
    return _inputQueue.enqueue(command.wire, captured, outgoing);
  }

  bool _admitsInput(String command, Json params, RemoteBinding binding) =>
      presentation.admitsQueuedInput(
        binding,
        command,
        params,
        foreground: acceptsInput,
        ownerCurrent: view?.isCurrent == true,
      );

  Future<void> _dispatchInput(
    String command,
    Json params,
    RemoteBinding binding,
  ) => sendNow(command, params, binding);

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
    resizeTimer?.cancel();
    scheduledDisplaySize = null;
    scheduledDisplayBinding = null;
    releaseDeviceView();
    setState(() => presentation.leave());
    final feedback = ScaffoldMessenger.maybeOf(context);
    final left = Completer<void>();
    final owned = view;
    final id = sessionId;
    Future<void> reportKeepActiveCleanup(Json receipt) async {
      final cleanup = jsonObject(receipt['keepActiveCleanup']);
      if (receipt['sessionId'] != id ||
          receipt['status'] != 'stopped' ||
          (cleanup['cleanupConfirmed'] != false &&
              cleanup['status'] != 'cleanup_unconfirmed')) {
        return;
      }
      final reason = value(jsonObject(cleanup['error']), 'reason', '请稍后重新检查。');
      await left.future;
      if (feedback?.mounted == true) {
        feedback!.showSnackBar(glassSnackBar('窗口已关闭，保持唤醒服务释放尚未确认：$reason'));
      }
    }

    final lock =
        owned?.isCurrent == true &&
        presentation.controlAvailable &&
        !presentation.stateUnverified &&
        jsonObject(
              jsonObject(
                controller.snapshot().settings['deviceSettings'],
              )[value(widget.device, 'id')],
            )['lockOnClose'] ==
            true;
    final lastPage = releasePhonePage?.call() == true;
    releasePhonePage = null;
    if (id.isNotEmpty && owned?.ownsBinding == true) {
      // Capture exact ownership before leaving. Closing destroys this window;
      // temporary occlusion alone continues to use pause/resume.
      final cleanup = releaseInputs().then((_) async {
        if (lock &&
            lastPage &&
            !controller.hasPhoneControlPages(value(widget.device, 'id')) &&
            owned!.ownsBinding) {
          try {
            await controller.execute(InteropCommand.sessionKey, {
              'sessionId': id,
              'keyCode': 223,
              'action': 'down',
            });
            await controller.execute(InteropCommand.sessionKey, {
              'sessionId': id,
              'keyCode': 223,
              'action': 'up',
            });
          } catch (failure) {
            unawaited(
              left.future.then((_) {
                if (feedback?.mounted == true) {
                  feedback!.showSnackBar(
                    glassSnackBar('锁屏尚未确认：${remoteFailure(failure)}'),
                  );
                }
              }),
            );
          }
        }
        if (owned!.ownsBinding) {
          final receipt = await owned.close();
          await reportKeepActiveCleanup(receipt);
        }
      });
      presentation.revokeControl();
      unawaited(
        cleanup.catchError((Object failure) async {
          await left.future;
          if (feedback?.mounted == true) {
            feedback!.showSnackBar(
              glassSnackBar('关闭窗口尚未确认：${remoteFailure(failure)}'),
            );
          }
        }),
      );
    } else if (id.isNotEmpty && owned == null && !presentation.sessionEnded) {
      // A startup without pixels can still own an operation record or remote
      // window. Explicit close releases that exact identity as well.
      unawaited(
        controller
            .execute(InteropCommand.sessionStop, {
              'sessionId': id,
              'keepTask': true,
            })
            .then((receipt) async {
              await reportKeepActiveCleanup(receipt);
              return receipt;
            })
            .catchError((Object failure) async {
              await left.future;
              if (feedback?.mounted == true) {
                feedback!.showSnackBar(
                  glassSnackBar('关闭窗口尚未确认：${remoteFailure(failure)}'),
                );
              }
              return <String, dynamic>{};
            }),
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) closePage<void>(context);
    await WidgetsBinding.instance.endOfFrame;
    left.complete();
  }

  @override
  void dispose() {
    resizeTimer?.cancel();
    screenStateTimer?.cancel();
    releasePhonePage?.call();
    if (!initialViewport.isCompleted) initialViewport.complete(Size.zero);
    releaseDeviceView();
    presentation.invalidateStart();
    final release = releaseInputs();
    unawaited(
      release.then<void>(
        (_) => _inputQueue.close(),
        onError: (Object _, StackTrace _) => _inputQueue.close(),
      ),
    );
    final ownedView = view;
    if (!presentation.exiting && ownedView != null) {
      unawaited(
        ownedView
            .close(afterInput: release)
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
    trace('display.scheduled target=$target binding=$binding viewport=$size');
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
        trace('display.request target=$target binding=$binding');
        await controller.execute(InteropCommand.sessionDisplay, {
          'sessionId': binding.$1,
          'displayWidth': target.width,
          'displayHeight': target.height,
        });
        trace(
          'display.return target=$target current=${presentation.binding} submitted=$binding',
        );
        if (mounted && binding == presentation.binding) {
          appliedDisplaySize = target;
        }
      } catch (failure) {
        trace(
          'display.failed target=$target binding=$binding failure=$failure',
        );
        if (mounted && binding == presentation.binding) {
          showRemoteNotice('屏幕比例调整未确认：${remoteFailure(failure)}');
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
    final width = presentation.imageWidth;
    final height = presentation.imageHeight;
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
              if (popped) return;
              if (presentation.connecting) {
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
                if (!focused) unawaited(releaseInputs());
              },
              child: Scaffold(
                backgroundColor: Colors.black,
                resizeToAvoidBottomInset: true,
                bottomNavigationBar:
                    showNavigationBar && !presentation.connecting
                    ? _RemoteNavigationBar(
                        enabled: canSendInput,
                        onBack: () => pressNavigationKey(4),
                        onHome: () => pressNavigationKey(3),
                        onRecent: () => pressNavigationKey(187),
                      )
                    : null,
                // Video consumes the full drawable viewport. Overlay controls
                // apply their own safe and system gesture insets.
                body: Stack(
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
                      Positioned.fill(
                        child: AmbientLoadingField(
                          semanticsLabel: widget.packageName == null
                              ? '正在打开手机屏幕'
                              : '正在打开独立窗口',
                          footer: GlassSurfaceGroup(
                            child: Glass(
                              radius: DesignTokens.roundedFull,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size.fromHeight(
                                    DesignTokens.componentButtonSecondaryHeight,
                                  ),
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                                onPressed: presentation.exiting
                                    ? null
                                    : () => unawaited(leave()),
                                icon: Icon(
                                  presentation.exiting
                                      ? LucideIcons.loaderCircle
                                      : LucideIcons.x,
                                  size: DesignTokens.componentIconActionSize,
                                ),
                                label: Text(
                                  presentation.exiting ? '正在关闭…' : '取消打开',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (presentation.qualityRebuilding)
                      const Align(
                        alignment: Alignment.bottomCenter,
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.all(DesignTokens.spacingMd),
                            child: Glass(
                              padding: EdgeInsets.all(DesignTokens.spacingMd),
                              child: Text('正在调整画面…'),
                            ),
                          ),
                        ),
                      ),
                    if (!presentation.connecting &&
                        (presentation.error != null || presentation.paused) &&
                        presentation.errorCode != 'device_asleep')
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
                              roomBelow >= DesignTokens.componentRowHeight * 2;
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
                                key: const ValueKey('remote-recovery-content'),
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
                                              : presentation.qualityRetryable
                                              ? '画面调整未完成'
                                              : presentation.appLaunchUnknown
                                              ? '应用打开结果待核对'
                                              : presentation.stateUnverified
                                              ? '正在核验会话状态'
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
                                        if (widget.packageName != null &&
                                            presentation.error != null &&
                                            !presentation.qualityRetryable &&
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
                                              : presentation.qualityRetryable
                                              ? () => QualityRoute(
                                                  deviceId: value(
                                                    widget.device,
                                                    'id',
                                                  ),
                                                ).push<void>(context)
                                              : presentation.appLaunchUnknown
                                              ? checkAppLaunch
                                              : (presentation.reconcileOnly
                                                    ? reconcileState
                                                    : start),
                                          child: Text(
                                            presentation.qualityRetryable
                                                ? '画面设置'
                                                : presentation.appLaunchUnknown
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
                    if (screenOn == false ||
                        screenLocked == true ||
                        (screenOn == null &&
                            screenLocked == null &&
                            presentation.errorCode == 'device_asleep'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom:
                            math.max(MediaQuery.paddingOf(context).bottom, 24) +
                            48,
                        child: Center(
                          child: GlassActionIcon(
                            tooltip: '点亮屏幕',
                            onPressed: waking ? null : wakeScreen,
                            icon: const Icon(
                              LucideIcons.sun,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (!presentation.connecting)
                      ExitHandle(
                        onExit: leave,
                        independent: widget.packageName != null,
                        onLock: canSendInput
                            ? () => pressNavigationKey(223)
                            : null,
                        onConvert:
                            canSendInput &&
                                !converting &&
                                (int.tryParse(
                                          value(widget.device, 'apiLevel'),
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
                            ? () => unawaited(
                                send(InteropCommand.sessionRotate, {}),
                              )
                            : null,
                        deviceLabel: deviceName(widget.device),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RemoteNavigationBar extends StatelessWidget {
  const _RemoteNavigationBar({
    required this.enabled,
    required this.onBack,
    required this.onHome,
    required this.onRecent,
  });

  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onRecent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconColor = enabled
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);
    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant,
                width: DesignTokens.spacingHairline,
              ),
            ),
          ),
          child: SizedBox(
            height: DesignTokens.componentPageHeaderHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _button(
                  tooltip: '返回',
                  enabled: enabled,
                  onPressed: onBack,
                  icon: Icons.arrow_back,
                  color: iconColor,
                ),
                _button(
                  tooltip: '主屏幕',
                  enabled: enabled,
                  onPressed: onHome,
                  icon: Icons.circle_outlined,
                  color: iconColor,
                ),
                _button(
                  tooltip: '最近任务',
                  enabled: enabled,
                  onPressed: onRecent,
                  icon: Icons.crop_square,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
  }) => SizedBox(
    width: 72,
    height: DesignTokens.componentPageHeaderHeight,
    child: IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      iconSize: DesignTokens.componentIconSize,
      icon: Icon(icon, color: color),
    ),
  );
}
