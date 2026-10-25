import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/media/session_view_registry.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart'
    show confirm, glassSnackBar;
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/presentation/remote_failure.dart';
import 'package:scrcpy_connect/media/remote_display_settings.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

import 'remote_connection_recovery.dart';
import 'remote_input_owner.dart';
import 'remote_presentation.dart';
import 'remote_window.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:media_codec/media_codec.dart';
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
  bool adjustmentShown = false;
  SessionViewLease? get view => window.view;
  ModalRoute<dynamic>? observedRoute;
  late final RemoteWindow window;
  RemotePresentation get presentation => window.presentation;
  final connectionRecovery = RemoteConnectionRecovery();
  bool restoringConnection = false;
  final remoteMessenger = GlobalKey<ScaffoldMessengerState>();
  RemoteBinding? keepActiveNoticeBinding;
  (String, String)? keepActiveErrorKey;
  String? pendingKeepActiveNotice;
  bool keepActiveNoticeScheduled = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? remoteNoticeTail;
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
    await controller.execute(ApplicationCommand.devicesWake, {
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
      // 明确唤醒可以解除启动唤醒失败，但后续通用重试不能自动重放失败请求。
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
        ApplicationCommand.sessionScreenshot,
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
      // 排队的 SnackBar 无法单独撤销；先保留提示，前一条结束后重新核对路由与绑定。
      if (messenger == null || message == null || remoteNoticeTail != null) {
        return;
      }
      pendingKeepActiveNotice = null;
      showRemoteNotice(message);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  late final RemoteInputOwner inputs;
  TextEditingController get text => inputs.text;
  Future<void> get inputQueue => inputs.idle;
  StreamSubscription<Json>? eventSubscription;
  AppController get controller => widget.controller;
  String get sessionId => presentation.sessionId;
  @override
  void initState() {
    super.initState();
    window = RemoteWindow(
      controller: controller,
      deviceId: value(widget.device, 'id'),
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
          (await controller.execute(ApplicationCommand.sessionList, {
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
        // 请求前先消耗新窗口唤醒意图，失败或缺少回执时不能随重建和通用重试重放。
        await (newWindowWake ??= requestWake());
        if (!mounted || !presentation.acceptsStart(attempt)) return;
      }
      submittedAppStart = retained == null && widget.packageName != null;
      final result =
          retained ??
          await controller.execute(ApplicationCommand.sessionStart, {
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
          // 打开请求已提交；迟到结果仅用于核验身份，不能触发再次打开或停止真实任务。
          if (sessionId.isEmpty) {
            setState(() => presentation.retainUnverifiedStart(result));
          }
          return;
        }
        if (retained == null) {
          final staleId = value(result, 'sessionId', value(result, 'id'));
          if (staleId.isNotEmpty && staleId != sessionId) {
            try {
              await controller.execute(ApplicationCommand.sessionStop, {
                'sessionId': staleId,
                'keepTask': true,
                if (widget.packageName != null) 'keepLaunchRecord': true,
              });
            } catch (_) {
              // 迟到回执不能重新创建已释放视图。
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
      window.bind(visible: result['status'] != 'paused');
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
      // 桥接只在实际解码像素后返回纹理；早期输出事件可能先于页面绑定。
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
    // 副作用提交前先消耗意图，缺少回执意味着结果未知，恢复画面不能自动重放。
    switch (action.tool) {
      case RemoteTool.rotate:
        await send(ApplicationCommand.sessionRotate, {});
      case RemoteTool.screen:
        await send(ApplicationCommand.sessionScreen, {'mode': action.value});
      case RemoteTool.text:
        await send(ApplicationCommand.sessionText, {'text': action.value});
      case RemoteTool.launchApp:
        await send(ApplicationCommand.sessionLaunch, {
          'deviceId': widget.device['id'],
          'packageName': action.value,
        });
      case RemoteTool.key:
        final code = action.value! as int;
        await inputs.tapKey(code);
    }
  }

  void showUnknownAppLaunch(Json record) {
    setState(() => presentation.showUnknownAppLaunch(record));
  }

  void detachForUnknownAppLaunch(Json record) {
    setState(() => window.detachUnknownLaunch(record, releaseInputs));
  }

  Future<void> checkAppLaunch() async {
    setState(() => presentation.checking());
    try {
      final listed = objects(
        (await controller.execute(ApplicationCommand.sessionList, {
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
        await controller.execute(ApplicationCommand.sessionStop, {
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
        // 替换会话取得新身份前接受的停止，不能被迟到列表或启动回执撤销。
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
            !hasDecodedFrameEvidence(data)) {
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
      // 桥接只在完整读取栅栏通过后发布 state.resynced，命令回执本身不能解除画面门禁。
      await controller.execute(ApplicationCommand.stateReconcile);
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
    // 异步恢复启动前同步消耗恢复意图，不重放路由最初携带的工具动作。
    presentation.suppressInitialAction();
    window.abandonEndedSession();
    unawaited(start(recoveringConnection: true));
  }

  Future<void> pauseView() async {
    final operation = window.pause(releaseInputs);
    if (mounted) setState(() {});
    await operation;
    if (mounted) setState(() {});
  }

  void focusVisibleDevice() {
    // 保留页面可能在其他设备可见后才完成启动或恢复，只有当前路由和会话所有者可设置焦点。
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
    showPendingKeepActiveNotice();
    await applyPendingInitialAction();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(releaseInputs());
    if (state == AppLifecycleState.inactive || sessionId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      showPendingKeepActiveNotice();
      // 短暂 inactive 保留画面流但可能推迟视口调整，恢复时即使无需切换可见性也要继续调整。
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

  void requestImeFocus() {
    // Android 会先显示系统栏再报告键盘边距；过渡两阶段均保留已确认的显示尺寸。
    waitingForIme = true;
    imeRequestedWindowSize = MediaQuery.sizeOf(context);
    resizeTimer?.cancel();
    inputFocus.requestFocus();
  }

  bool get imeBlocksDisplaySizing =>
      waitingForIme || MediaQuery.viewInsetsOf(context).bottom > 0;

  void inputFocusChanged() {
    if (!inputFocus.hasFocus) {
      inputs.resetTextInput();
      if (mounted && waitingForIme) {
        setState(() => waitingForIme = false);
      }
    }
  }

  Future<void> releaseInputs({RemoteBinding? binding}) =>
      inputs.releaseInputs(binding: binding);
  Future<void> releasePointers({RemoteBinding? binding}) =>
      inputs.releasePointers(binding: binding);
  Future<void> send(
    ApplicationCommand command,
    Json params, {
    RemoteBinding? binding,
  }) => inputs.send(command, params, binding: binding);
  KeyEventResult key(FocusNode node, KeyEvent event) =>
      inputs.key(event, ime: ime);
  void pointer(PointerEvent event, String action, Size viewport, Size source) =>
      inputs.pointer(event, action, viewport, source);
  void hover(PointerHoverEvent event, Size viewport, Size source) =>
      inputs.hover(event, viewport, source);
  void scroll(PointerSignalEvent event, Size viewport, Size source) =>
      inputs.scroll(event, viewport, source);

  void pressNavigationKey(int code) {
    if (!canSendInput) return;
    unawaited(
      send(ApplicationCommand.sessionKey, {'keyCode': code, 'action': 'down'}),
    );
    unawaited(
      send(ApplicationCommand.sessionKey, {'keyCode': code, 'action': 'up'}),
    );
  }

  Future<void> leave() async {
    if (presentation.exiting) return;
    resizeTimer?.cancel();
    scheduledDisplaySize = null;
    scheduledDisplayBinding = null;
    final feedback = ScaffoldMessenger.maybeOf(context);
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
            glassSnackBar('锁屏尚未确认：${remoteFailure(failure)}'),
          );
        }
        if (result.closeFailure case final failure?) {
          feedback!.showSnackBar(
            glassSnackBar('关闭窗口尚未确认：${remoteFailure(failure)}'),
          );
        }
        final receipt = result.receipt;
        final keepActive = jsonObject(receipt['keepActiveCleanup']);
        if (receipt['sessionId'] == id &&
            receipt['status'] == 'stopped' &&
            (keepActive['cleanupConfirmed'] == false ||
                keepActive['status'] == 'cleanup_unconfirmed')) {
          final reason = value(
            jsonObject(keepActive['error']),
            'reason',
            '请稍后重新检查。',
          );
          feedback!.showSnackBar(glassSnackBar('窗口已关闭，保持唤醒服务释放尚未确认：$reason'));
        }
      }),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) closePage<void>(context);
    await WidgetsBinding.instance.endOfFrame;
    left.complete();
  }

  @override
  void dispose() {
    resizeTimer?.cancel();
    screenStateTimer?.cancel();
    if (!initialViewport.isCompleted) initialViewport.complete(Size.zero);
    final release = window.dispose(releaseInputs);
    inputs.dispose(afterInput: release);
    sessionRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    eventSubscription?.cancel();
    inputFocus.removeListener(inputFocusChanged);
    inputFocus.dispose();
    keyboardFocus.dispose();
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
    // 帧可能比防抖间隔更快重建布局，仅目标尺寸或绑定变化时重置待调整任务。
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
        await controller.execute(ApplicationCommand.sessionDisplay, {
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
      // 手机旋转会改变自然坐标映射，即使主控视口未变化，也要按新几何形状重设一次。
      requestedDisplaySize = null;
      observeViewport(displayViewport!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold 调整内容区后会移除底部 viewInset；读取路由原始边距，避免输入法重新定义显示尺寸。
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible ||
        (waitingForIme &&
            imeRequestedWindowSize != MediaQuery.sizeOf(context))) {
      // 硬件键盘未必产生输入法边距；实际宿主尺寸变化仍需适应，同窗口的临时系统栏不能提前结束等待。
      waitingForIme = false;
    }
    if (keyboardVisible || waitingForIme) resizeTimer?.cancel();
    final width = presentation.imageWidth;
    final height = presentation.imageHeight;
    final texture = int.tryParse('${presentation.session?['textureId']}');
    final valid = texture != null && width > 0 && height > 0;
    // 应用消息可跨路由显示；远控使用独立消息区域，防止本机页面的结果遮住手机画面。
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
                // 视频占满可绘制视口，叠加控件自行扣除安全区与系统手势边距。
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
                            onPointerHover: (event) => hover(
                              event,
                              constraints.biggest,
                              Size(width, height),
                            ),
                            onPointerSignal: (event) => scroll(
                              event,
                              constraints.biggest,
                              Size(width, height),
                            ),
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
                                ? MediaCodecView(
                                    textureId: texture,
                                    width: width.round(),
                                    height: height.round(),
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
                          // 较矮的横屏使用退出控件旁边的空间，较高布局则预留顶部区域。
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
                              send(ApplicationCommand.sessionKey, {
                                'keyCode': 66,
                                'action': 'down',
                              }),
                            );
                            unawaited(
                              send(ApplicationCommand.sessionKey, {
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
                                send(ApplicationCommand.sessionRotate, {}),
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
