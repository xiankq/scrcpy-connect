import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/remote_failure.dart';
import 'package:scrcpy_connect/utils/source_coordinates.dart';

import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_input_queue.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_presentation.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_window.dart';

class _HeldKey {
  _HeldKey(this.binding);

  final RemoteBinding binding;
}

/// 单窗口输入所有者：捕获绑定和采集代际，维护手势、持键与组合编辑，并有序排空释放。
/// 页面只提供当前准入资格与呈现通知，不持有协议输入集合或队列。
class RemoteInputOwner {
  RemoteInputOwner({
    required this.window,
    required this._foreground,
    required this._enabled,
    required this._onChanged,
    required this._onUnknownLaunch,
  }) {
    // 输入法可能只结束组合而不改文字，因此不能仅依赖控件的 onChanged。
    text.addListener(_textChanged);
  }

  final RemoteWindow window;
  final bool Function() _foreground;
  final bool Function() _enabled;
  final void Function() _onChanged;
  final void Function(Json) _onUnknownLaunch;
  bool _disposed = false;
  static const inputSentinel = '\u200B';
  final text = TextEditingController(text: inputSentinel);
  final _activePointers = <int>{};
  final _pointerPositions = <int, Json>{};
  final _heldKeys = <int, _HeldKey>{};
  final _keyRepeats = <int, int>{};
  final _bindingCaptures = <RemoteBinding, int>{};
  String _previousText = inputSentinel;
  bool _resettingText = false;
  RemotePresentation get presentation => window.presentation;
  String get sessionId => presentation.sessionId;
  bool get canSendInput => !_disposed && _enabled();
  late final _inputQueue = RemoteInputQueue(
    dispatch: _dispatchInput,
    admits: _admitsInput,
  );
  Future<void> get idle => _inputQueue.idle;

  void _trace(String detail) {
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.remote ${DateTime.now().millisecondsSinceEpoch}] $detail',
      );
    }
  }

  Future<void> releaseInputs({RemoteBinding? binding}) {
    final outgoing = binding ?? presentation.binding;
    resetTextInput();
    var completion = releasePointers(binding: binding);
    final keys = Map<int, _HeldKey>.from(_heldKeys);
    _heldKeys.clear();
    _keyRepeats.clear();
    if (!presentation.controlAvailable && binding == null) return completion;
    for (final entry in keys.entries) {
      if (entry.value.binding != outgoing) {
        continue;
      }
      completion = send(ApplicationCommand.sessionKey, {
        'sessionId': entry.value.binding.$1,
        'keyCode': entry.key,
        'action': 'up',
      }, binding: outgoing);
    }
    return completion;
  }

  Future<void> releasePointers({RemoteBinding? binding}) {
    final releases = _pointerPositions.values.toList();
    _activePointers.clear();
    _pointerPositions.clear();
    if (!presentation.controlAvailable && binding == null) {
      return presentation.reconcileOnly ? idle : Future<void>.value();
    }
    // 物理按键松开可能已入队但持有记录已移除，停止或替换会话前仍需排空输入。
    Future<void> completion = idle;
    for (final params in releases) {
      completion = send(ApplicationCommand.sessionTouch, {
        ...params,
        'action': 'cancel',
        'pressure': 0,
      }, binding: binding);
    }
    return completion;
  }

  Future<void> send(
    ApplicationCommand command,
    Json params, {
    RemoteBinding? binding,
  }) {
    // 队列项持有准入时的绑定，迟到请求或释放不能继承替换会话的身份。
    final outgoing = binding ?? presentation.binding;
    final input = const {
      'session.touch',
      'session.key',
      'session.text',
      'session.scroll',
    }.contains(command.wire);
    final currentCapture = presentation.session?['captureGeneration'];
    if (outgoing == presentation.binding && currentCapture is int) {
      _bindingCaptures[outgoing] = currentCapture;
      while (_bindingCaptures.length > 32) {
        _bindingCaptures.remove(_bindingCaptures.keys.first);
      }
    }
    final captured = {
      'sessionId': outgoing.$1,
      if (input && _bindingCaptures[outgoing] != null)
        'captureGeneration': _bindingCaptures[outgoing],
      ...params,
    };
    return _inputQueue.enqueue(command.wire, captured, outgoing).catchError((
      Object error,
    ) {
      if (!_disposed && outgoing == presentation.binding) {
        presentation.revokeControl();
        presentation.failInput('$error', 'control_busy');
        _onChanged();
      }
    });
  }

  bool _admitsInput(String command, Json params, RemoteBinding binding) =>
      presentation.admitsQueuedInput(
        binding,
        command,
        params,
        foreground: _foreground(),
        ownerCurrent: window.view?.isCurrent == true,
      );

  Future<void> _dispatchInput(
    String command,
    Json params,
    RemoteBinding binding,
  ) => _sendNow(command, params, binding);

  Future<void> _sendNow(
    String command,
    Json params,
    RemoteBinding binding,
  ) async {
    _trace('request.begin command=$command');
    try {
      await window.controller.request(command, params);
      _trace('request.complete command=$command');
    } catch (e) {
      _trace('request.failed command=$command kind=${e.runtimeType}');
      if (!_disposed &&
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
            details['deviceId'] == window.deviceId &&
            details['packageName'] == params['packageName'] &&
            details['linkedSessionId'] == params['sessionId']) {
          _onUnknownLaunch(details);
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
        presentation.failInput(remoteFailure(e), remoteFailureCode(e));
        _onChanged();
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
      _activePointers.add(event.pointer);
    }
    if (!_activePointers.contains(event.pointer)) return;
    if (point == null) {
      // 在最后有效坐标结束远端手势，忽略该物理指针直到抬起；移回画面不能创建新拖动。
      final previous = _pointerPositions.remove(event.pointer);
      _activePointers.remove(event.pointer);
      if (previous != null) {
        unawaited(
          send(ApplicationCommand.sessionTouch, {
            ...previous,
            'action': 'cancel',
            'pressure': 0,
          }),
        );
      }
      return;
    }
    final previousButtons =
        _pointerPositions[event.pointer]?['buttons'] as int? ?? 0;
    final changedButtons = (previousButtons ^ event.buttons) & 31;
    final wireAction =
        event.kind == PointerDeviceKind.mouse &&
            action == 'move' &&
            changedButtons != 0
        ? (event.buttons & changedButtons != 0 ? 'down' : 'up')
        : action;
    final params = <String, dynamic>{
      'action': wireAction,
      'pointerId': event.pointer,
      'x': point.dx.round().clamp(0, source.width.round() - 1),
      'y': point.dy.round().clamp(0, source.height.round() - 1),
      'pressure': wireAction == 'up' || wireAction == 'cancel'
          ? 0
          : _normalizedPressure(event),
      if (event.kind == PointerDeviceKind.mouse) ...{
        'mouse': true,
        'buttons': event.buttons & 31,
        'actionButton': (wireAction == 'down' || wireAction == 'up')
            ? changedButtons
            : 0,
      },
      'screenWidth': source.width.round(),
      'screenHeight': source.height.round(),
    };
    if (action == 'down' || action == 'move') {
      _pointerPositions[event.pointer] = params;
    }
    unawaited(send(ApplicationCommand.sessionTouch, params));
    if (action == 'up' || action == 'cancel') {
      _activePointers.remove(event.pointer);
      _pointerPositions.remove(event.pointer);
    }
  }

  double _normalizedPressure(PointerEvent event) {
    final span = event.pressureMax - event.pressureMin;
    if (!event.pressure.isFinite || !span.isFinite || span <= 0) return 1;
    return ((event.pressure - event.pressureMin) / span).clamp(0.0, 1.0);
  }

  void hover(PointerHoverEvent event, Size viewport, Size source) {
    if (!canSendInput || event.kind != PointerDeviceKind.mouse) return;
    final point = sourcePoint(event.localPosition, viewport, source);
    if (point == null) return;
    unawaited(
      send(ApplicationCommand.sessionTouch, {
        'action': 'hover',
        'mouse': true,
        'pointerId': 0,
        'x': point.dx.round().clamp(0, source.width.round() - 1),
        'y': point.dy.round().clamp(0, source.height.round() - 1),
        'screenWidth': source.width.round(),
        'screenHeight': source.height.round(),
        'pressure': 0,
        'buttons': event.buttons & 31,
      }),
    );
  }

  void scroll(PointerSignalEvent event, Size viewport, Size source) {
    if (!canSendInput || event is! PointerScrollEvent) return;
    final point = sourcePoint(event.localPosition, viewport, source);
    if (point == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      unawaited(
        send(ApplicationCommand.sessionScroll, {
          'x': point.dx.round().clamp(0, source.width.round() - 1),
          'y': point.dy.round().clamp(0, source.height.round() - 1),
          'screenWidth': source.width.round(),
          'screenHeight': source.height.round(),
          // Flutter 使用逻辑像素，普通滚轮一格对应 20 像素。
          'hscroll': -event.scrollDelta.dx / 20,
          'vscroll': -event.scrollDelta.dy / 20,
          'buttons': event.buttons & 31,
        }),
      );
    });
  }

  void resetTextInput() {
    _previousText = inputSentinel;
    _resettingText = true;
    text.value = const TextEditingValue(
      text: inputSentinel,
      selection: TextSelection.collapsed(offset: 1),
    );
    _resettingText = false;
  }

  void _textChanged() {
    if (_resettingText) return;
    if (!canSendInput) {
      resetTextInput();
      return;
    }
    // 只发送已提交的输入法文字，拼音和候选组合保留在本机。
    if (text.value.composing.isValid && !text.value.composing.isCollapsed) {
      return;
    }
    final next = text.text;
    final before = _previousText.characters.toList();
    final after = next.characters.toList();
    var common = 0;
    while (common < before.length &&
        common < after.length &&
        before[common] == after[common]) {
      common++;
    }
    for (var i = common; i < before.length; i++) {
      unawaited(
        send(ApplicationCommand.sessionKey, {'keyCode': 67, 'action': 'down'}),
      );
      unawaited(
        send(ApplicationCommand.sessionKey, {'keyCode': 67, 'action': 'up'}),
      );
    }
    final added = after.skip(common).join().replaceAll(inputSentinel, '');
    if (added.isNotEmpty) {
      unawaited(send(ApplicationCommand.sessionText, {'text': added}));
    }
    _previousText = next;
    if (after.length > 128) {
      final retained =
          '$inputSentinel${after.skip(after.length - 64).join().replaceAll(inputSentinel, '')}';
      _previousText = retained;
      _resettingText = true;
      text.value = TextEditingValue(
        text: retained,
        selection: TextSelection.collapsed(offset: retained.length),
      );
      _resettingText = false;
    }
    // 保留一个不可见字符，使本机缓冲区清空后退格仍能删除远端已有文字。
    if (next.isEmpty) {
      resetTextInput();
    }
  }

  KeyEventResult key(KeyEvent event, {required bool ime}) {
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
      LogicalKeyboardKey.home: 122,
      LogicalKeyboardKey.end: 123,
      LogicalKeyboardKey.pageUp: 92,
      LogicalKeyboardKey.pageDown: 93,
      LogicalKeyboardKey.insert: 124,
      LogicalKeyboardKey.controlLeft: 113,
      LogicalKeyboardKey.controlRight: 114,
      LogicalKeyboardKey.shiftLeft: 59,
      LogicalKeyboardKey.shiftRight: 60,
      LogicalKeyboardKey.altLeft: 57,
      LogicalKeyboardKey.altRight: 58,
      LogicalKeyboardKey.metaLeft: 117,
      LogicalKeyboardKey.metaRight: 118,
      LogicalKeyboardKey.space: 62,
      LogicalKeyboardKey.minus: 69,
      LogicalKeyboardKey.equal: 70,
      LogicalKeyboardKey.bracketLeft: 71,
      LogicalKeyboardKey.bracketRight: 72,
      LogicalKeyboardKey.backslash: 73,
      LogicalKeyboardKey.semicolon: 74,
      LogicalKeyboardKey.quote: 75,
      LogicalKeyboardKey.slash: 76,
      LogicalKeyboardKey.backquote: 68,
      LogicalKeyboardKey.comma: 55,
      LogicalKeyboardKey.period: 56,
      LogicalKeyboardKey.delete: 112,
    };
    final logical = event.logicalKey.keyId;
    final code =
        codes[event.logicalKey] ??
        (logical >= 0x61 && logical <= 0x7a ? logical - 0x61 + 29 : null) ??
        (logical >= 0x30 && logical <= 0x39 ? logical - 0x30 + 7 : null) ??
        (event.logicalKey.keyId >= LogicalKeyboardKey.f1.keyId &&
                event.logicalKey.keyId <= LogicalKeyboardKey.f12.keyId
            ? event.logicalKey.keyId - LogicalKeyboardKey.f1.keyId + 131
            : null);
    final keyboard = HardwareKeyboard.instance;
    final metaState =
        (keyboard.isShiftPressed ? 0x1 : 0) |
        (keyboard.isAltPressed ? 0x2 : 0) |
        (keyboard.isControlPressed ? 0x1000 : 0) |
        (keyboard.isMetaPressed ? 0x10000 : 0) |
        (keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock)
            ? 0x100000
            : 0) |
        (keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock)
            ? 0x200000
            : 0);

    if (event is KeyUpEvent && code != null) {
      final held = _heldKeys.remove(code);
      _keyRepeats.remove(code);
      if (held == null) return KeyEventResult.ignored;
      if (held.binding == presentation.binding &&
          presentation.controlAvailable) {
        unawaited(
          send(ApplicationCommand.sessionKey, {
            'sessionId': held.binding.$1,
            'keyCode': code,
            if (metaState != 0) 'metaState': metaState,
            'action': 'up',
          }),
        );
      }
      return KeyEventResult.handled;
    }
    if (!canSendInput || (ime && code != 4)) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        event.character?.isNotEmpty == true &&
        event.character!.runes.any((rune) => rune > 127) &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      unawaited(
        send(ApplicationCommand.sessionText, {'text': event.character}),
      );
      return KeyEventResult.handled;
    }
    if (code != null) {
      if (event is KeyRepeatEvent && !_heldKeys.containsKey(code)) {
        return KeyEventResult.ignored;
      }
      _heldKeys[code] = _HeldKey(presentation.binding);
      final repeat = event is KeyRepeatEvent ? (_keyRepeats[code] ?? 0) + 1 : 0;
      _keyRepeats[code] = repeat;
      unawaited(
        send(ApplicationCommand.sessionKey, {
          'keyCode': code,
          if (metaState != 0) 'metaState': metaState,
          if (repeat != 0) 'repeat': repeat,
          'action': event is KeyUpEvent ? 'up' : 'down',
        }),
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.character?.isNotEmpty == true) {
      unawaited(
        send(ApplicationCommand.sessionText, {'text': event.character}),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> tapKey(int code) async {
    final held = _HeldKey(presentation.binding);
    _heldKeys[code] = held;
    try {
      await send(ApplicationCommand.sessionKey, {
        'keyCode': code,
        'action': 'down',
      }, binding: held.binding);
    } finally {
      // 生命周期已排队释放或新按键接管后，旧工具动作不能再次释放，更不能继承新捕获。
      if (identical(_heldKeys[code], held)) {
        _heldKeys.remove(code);
        await send(ApplicationCommand.sessionKey, {
          'keyCode': code,
          'action': 'up',
        }, binding: held.binding);
      }
    }
  }

  void dispose({required Future<void> afterInput}) {
    if (_disposed) return;
    _disposed = true;
    text.removeListener(_textChanged);
    text.dispose();
    unawaited(
      afterInput.then<void>(
        (_) => _inputQueue.close(),
        onError: (Object _, StackTrace _) => _inputQueue.close(),
      ),
    );
  }
}
