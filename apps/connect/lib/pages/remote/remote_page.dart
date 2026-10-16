import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/remote_input.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

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
  });
  final AppController controller;
  final Json device;
  final String? packageName;
  final Json? existingSession;
  final bool requestKeyboard;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
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
  bool controlAvailable = false;
  int bindingGeneration = 0;
  int startAttempt = 0;
  bool lifecyclePaused = false;
  bool adjustmentShown = false;

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
    if (!controlAvailable) return Future<void>.value();
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
    unawaited(start());
  }

  Future<void> start() async {
    final attempt = ++startAttempt;
    trace(
      'start.begin lifecycle=${WidgetsBinding.instance.lifecycleState?.name}',
    );
    setState(() {
      connecting = true;
      error = null;
      errorCode = null;
    });
    try {
      await releaseInputs();
      if (!mounted || exiting || attempt != startAttempt) return;
      controlAvailable = false;
      bindingGeneration++;
      final result =
          widget.existingSession ??
          await controller.request('session.start', {
            'deviceId': widget.device['id'],
            if (widget.packageName != null) 'packageName': widget.packageName,
          });
      if (!mounted || exiting || attempt != startAttempt) {
        if (widget.existingSession == null) {
          final staleId = value(result, 'sessionId', value(result, 'id'));
          if (staleId.isNotEmpty && staleId != sessionId) {
            try {
              await controller.request('session.stop', {
                'sessionId': staleId,
                'keepTask': true,
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
      unawaited(controller.focusDevice(value(widget.device, 'id')));
      setState(() {
        session = result;
        controlAvailable = sessionId.isNotEmpty && result['textureId'] != null;
        lifecyclePaused = false;
        connecting = false;
        paused = result['status'] == 'paused';
        if (widget.requestKeyboard && result['textureId'] != null) ime = true;
        if (result['textureId'] == null) {
          error = value(result, 'reason', '尚未获得设备的实时画面。请检查设备连接和视频能力。');
        }
      });
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

  void onEvent(Json event) {
    if (!mounted) return;
    final data = event['data'] is Map<Object?, Object?>
        ? jsonObject(event['data'])
        : <String, dynamic>{};
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
          if (next['textureId'] != null) {
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
        controlAvailable = false;
        unawaited(releaseInputs());
        setState(() {
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

  void showResourceAdjustment() {
    final message = value(session ?? {}, 'resourceAdjustment');
    if (adjustmentShown || message.isEmpty || session?['textureId'] is! int) {
      return;
    }
    adjustmentShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !exiting) feedback(context, message);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    trace(
      'lifecycle state=${state.name} bound=${sessionId.isNotEmpty} lifecyclePaused=$lifecyclePaused',
    );
    if (state != AppLifecycleState.resumed) {
      unawaited(releaseInputs());
    }
    // Inactive can mean a visible system prompt or temporary focus loss.
    // Only hidden/paused/detached make the capture genuinely invisible.
    if (state == AppLifecycleState.inactive || sessionId.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      if (!lifecyclePaused) return;
      lifecyclePaused = false;
      unawaited(send('session.resume', {}));
    } else {
      if (lifecyclePaused) return;
      lifecyclePaused = true;
      setState(() => paused = true);
      unawaited(send('session.pause', {}));
    }
  }

  Future<void> send(String command, Json params) async {
    // Queue entries keep the binding that accepted them. A late request or
    // release must never inherit a replacement session's identity.
    final id = sessionId;
    final generation = bindingGeneration;
    final captured = {'sessionId': id, ...params};
    inputQueue = inputQueue.then((_) async {
      if (!controlAvailable ||
          id.isEmpty ||
          id != sessionId ||
          generation != bindingGeneration) {
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
      if (mounted &&
          !exiting &&
          generation == bindingGeneration &&
          params['sessionId'] == sessionId) {
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
    if (sessionId.isNotEmpty) {
      try {
        await releaseInputs();
        await controller.request('session.stop', {
          'sessionId': sessionId,
          'keepTask': true,
        });
        controlAvailable = false;
      } catch (_) {
        /* Device task is retained even when transport has already ended. */
      }
    }
    if (mounted) closePage<void>(context);
  }

  @override
  void dispose() {
    startAttempt++;
    final release = releaseInputs();
    final ownedSession = sessionId;
    if (!exiting && ownedSession.isNotEmpty) {
      unawaited(
        release
            .then(
              (_) => controller.request('session.stop', {
                'sessionId': ownedSession,
                'keepTask': true,
              }),
            )
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
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
    return PopScope(
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
                              errorCode == 'device_asleep'
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
                            OutlinedButton(
                              onPressed: connecting ? null : start,
                              child: const Text('重新检查'),
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
                        send('session.key', {'keyCode': 66, 'action': 'down'}),
                      );
                      unawaited(
                        send('session.key', {'keyCode': 66, 'action': 'up'}),
                      );
                    },
                  ),
                ),
              ExitHandle(onExit: leave, deviceLabel: deviceName(widget.device)),
            ],
          ),
        ),
      ),
    );
  }
}
