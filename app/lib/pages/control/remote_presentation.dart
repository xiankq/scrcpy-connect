import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';

typedef RemoteBinding = (String, int);

enum RemoteResumeResult { stale, rendererNotReady, ready }

class RemoteStartTicket {
  const RemoteStartTicket._(this._attempt, this._stateEpoch);
  final int _attempt;
  final int _stateEpoch;
}

enum _Verification { verified, pending, ended }

enum _Launch { normal, unknown, closed }

enum _Visibility { visible, hidden, resuming }

/// 统一维护单路由的绑定、回执栅栏与输入许可；异步资源由窗口编排，控件生命周期由页面协调。
class RemotePresentation {
  VideoSessionView? _session;
  String? _error;
  String? _errorCode;
  bool _connecting = true;
  bool _hasPresentedFrame = false;
  bool _paused = false;
  bool _exiting = false;
  bool _initialActionApplied = false;
  bool _lifecyclePaused = false;
  bool _covered = false;
  bool _controlAvailable = false;
  bool _qualityRebuilding = false;
  bool _qualityFailed = false;
  VideoSessionView? _qualityOriginal;
  VideoOutputReceipt? _qualityOutput;
  VideoSessionView? _qualityReady;
  int? _qualityTarget;
  int _bindingGeneration = 0;
  int _startAttempt = 0;
  int _visibilityEpoch = 0;
  int _stateEpoch = 0;
  int? _reconciledSequence;
  bool _reconcileOnly = false;
  _Verification _verification = _Verification.verified;
  _Launch _launch = _Launch.normal;
  _Visibility _visibility = _Visibility.visible;
  final _detachedCleanupBindings = <RemoteBinding>{};

  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get connecting => _connecting;
  bool get awaitingFirstFrame => !_hasPresentedFrame;
  bool get paused => _paused;
  bool get exiting => _exiting;
  bool get lifecyclePaused => _lifecyclePaused;
  bool get covered => _covered;
  VideoSessionView? get session => _session;
  String get sessionId => _session?.sessionId ?? '';
  RemoteBinding get binding => (sessionId, _bindingGeneration);
  int get visibilityEpoch => _visibilityEpoch;
  bool get controlAvailable => _controlAvailable;
  bool get appLaunchUnknown => _launch == _Launch.unknown;
  bool get appLaunchClosed => _launch == _Launch.closed;
  bool get stateUnverified => _verification != _Verification.verified;
  bool get sessionEnded => _verification == _Verification.ended;
  bool get reconcileOnly => _reconcileOnly;
  bool get qualityRebuilding => _qualityRebuilding;
  bool get qualityRetryable => _qualityFailed;

  double get imageWidth =>
      (_session?.output?.decodedWidth ??
              _session?.session.decodedWidth ??
              _session?.session.width ??
              0)
          .toDouble();
  double get imageHeight =>
      (_session?.output?.decodedHeight ??
              _session?.session.decodedHeight ??
              _session?.session.height ??
              0)
          .toDouble();

  bool get imageGeometryReady {
    final width = _session?.session.width ?? 0;
    final height = _session?.session.height ?? 0;
    return width <= 0 ||
        height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0 ||
        (width / height - imageWidth / imageHeight).abs() < .005;
  }

  void deferStart() => _connecting = false;

  void failOperation(String reason, {String? code}) {
    _connecting = false;
    _error = reason;
    if (code != null) _errorCode = code;
  }

  void reportError(String reason) => _error = reason;

  void failInput(String reason, String? code) {
    _error = reason;
    _errorCode = code;
    _paused = true;
  }

  void cover(bool value) => _covered = value;

  bool lifecycleVisibility(bool visible) {
    if (_lifecyclePaused == !visible) return false;
    _lifecyclePaused = !visible;
    return true;
  }

  void suppressInitialAction() => _initialActionApplied = true;

  void allowInitialAction() => _initialActionApplied = false;

  bool takeInitialAction({
    required bool foreground,
    required bool ownerCurrent,
  }) {
    if (_initialActionApplied ||
        !canSendInput(foreground: foreground, ownerCurrent: ownerCurrent)) {
      return false;
    }
    _initialActionApplied = true;
    return true;
  }

  bool canSendInput({required bool foreground, required bool ownerCurrent}) =>
      foreground &&
      _controlAvailable &&
      !_paused &&
      !_connecting &&
      !_qualityRebuilding &&
      !_qualityFailed &&
      imageGeometryReady &&
      !_exiting &&
      _error == null &&
      ownerCurrent &&
      !_covered &&
      !_lifecyclePaused &&
      _visibility == _Visibility.visible &&
      !stateUnverified &&
      !appLaunchUnknown &&
      sessionId.isNotEmpty;

  bool canRecoverConnection({
    required bool foreground,
    required bool phoneScreen,
    required bool reconciliationPending,
    required bool routeCurrent,
  }) =>
      !_exiting &&
      !_covered &&
      foreground &&
      !_lifecyclePaused &&
      phoneScreen &&
      !appLaunchUnknown &&
      !stateUnverified &&
      !reconciliationPending &&
      routeCurrent;

  bool canResume({required bool foreground}) =>
      !appLaunchUnknown &&
      !_qualityRebuilding &&
      !_qualityFailed &&
      !stateUnverified &&
      sessionId.isNotEmpty &&
      !_covered &&
      !_exiting &&
      foreground;

  RemoteStartTicket beginStart() {
    _connecting = true;
    _error = null;
    _errorCode = null;
    return RemoteStartTicket._(++_startAttempt, _stateEpoch);
  }

  bool isLatestStart(RemoteStartTicket ticket) =>
      ticket._attempt == _startAttempt;

  bool acceptsStart(RemoteStartTicket ticket) =>
      !exiting && isLatestStart(ticket);

  bool requiresVerification(RemoteStartTicket ticket) =>
      !exiting && ticket._stateEpoch != _stateEpoch;

  void invalidateStart() => _startAttempt++;

  void replaceBinding() {
    _controlAvailable = false;
    _bindingGeneration++;
  }

  static VideoSessionView _withoutOutput(VideoSessionView view) => view
      .copyWith(session: view.session.copyWith(textureId: null), output: null);

  void retainUnverifiedStart(VideoSessionView result) {
    if (sessionId.isNotEmpty) return;
    _session = _withoutOutput(result);
    _launch = _Launch.normal;
    _verification = _Verification.pending;
    _connecting = false;
    _error = '暂时无法确认手机画面是否还在。请检查连接。';
  }

  void bindStart(
    VideoSessionView result, {
    required bool retained,
    required bool recoveringConnection,
    required bool submittedAppStart,
  }) {
    _session = result;
    _launch = _Launch.normal;
    if (recoveringConnection) _reconcileOnly = false;
    _controlAvailable = result.hasDecodedFrame;
    _visibility = _Visibility.visible;
    _lifecyclePaused = false;
    _connecting = retained && result.textureId != null;
    _paused = result.session.status == .paused;
    // 新捕获只以对应解码回执确认首帧；恢复的旧纹理仍须 resume 核验。
    if (!retained && result.hasDecodedFrame && imageGeometryReady) {
      _hasPresentedFrame = true;
    }
    if (result.session.qualityRebuilding) _beginQuality(result);
    if (result.outputRetained &&
        result.output!.captureGeneration != result.session.captureGeneration) {
      _beginQuality(result, target: result.session.captureGeneration);
      if (!result.session.qualityRebuilding) updateSession(result);
    }
    if (result.session.status == .failed && result.session.qualityRetryable) {
      _failQuality(result);
    }
    if (result.textureId == null) {
      if (submittedAppStart) _launch = _Launch.unknown;
      _error = failureCodeMessage(
        result.session.failureCode,
        fallback: '无法打开手机画面。请检查手机连接后重试。',
      );
    }
  }

  void failStart(
    String reason,
    String? code, {
    required bool submittedAppStart,
    VideoSessionView? uncertainSession,
  }) {
    _connecting = false;
    _error = reason;
    _errorCode = code;
    // 只有提交前的明确拒绝才能证明重试安全。
    if (submittedAppStart &&
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
        }.contains(code)) {
      _launch = _Launch.unknown;
      if (uncertainSession != null) _session = _withoutOutput(uncertainSession);
    }
  }

  void showUnknownAppLaunch(VideoSessionView? record) {
    _session = record == null ? null : _withoutOutput(record);
    _launch = _Launch.unknown;
    _verification = _Verification.verified;
    _connecting = false;
    _controlAvailable = false;
    _errorCode = 'app_launch_unknown';
    _error = '暂时无法确认应用是否已打开。请先查看手机屏幕。';
  }

  RemoteBinding permitDetachedCleanup() {
    final outgoing = binding;
    _detachedCleanupBindings.add(outgoing);
    return outgoing;
  }

  void finishDetachedCleanup(RemoteBinding outgoing) =>
      _detachedCleanupBindings.remove(outgoing);

  void detachBinding() {
    _visibilityEpoch++;
    replaceBinding();
    _visibility = _Visibility.hidden;
    _paused = true;
  }

  void closeUnknownAppLaunch({required bool resetInitialAction}) {
    _session = null;
    _launch = _Launch.closed;
    _verification = _Verification.verified;
    _reconcileOnly = false;
    _paused = false;
    _connecting = false;
    if (resetInitialAction) _initialActionApplied = false;
    _errorCode = null;
    _error = '本次打开记录已关闭，手机上的应用任务已保留。可明确选择重新打开。';
  }

  int beginReconciliation({VideoSessionView? initialSession, String? reason}) {
    if (initialSession != null) _session = initialSession;
    _stateEpoch++;
    _visibilityEpoch++;
    invalidateStart();
    // 页面捕获原绑定的释放输入前先冻结准入。
    _verification = _Verification.pending;
    _reconcileOnly = true;
    _initialActionApplied = true;
    _connecting = false;
    _paused = true;
    if (_visibility == _Visibility.resuming) _visibility = _Visibility.visible;
    _error = reason ?? '正在重新核对活动状态，完成前暂停操作。';
    _errorCode = null;
    return _stateEpoch;
  }

  bool acceptsReconciliation(int epoch) => !exiting && epoch == _stateEpoch;

  bool acceptsVisibilityFailure(int epoch) =>
      !exiting && epoch == _visibilityEpoch;

  /// 返回 false 表示重复快照，不应再触发捕获或焦点副作用。
  bool reconcile(
    RuntimeSnapshot snapshot, {
    required String? packageName,
    required String deviceId,
  }) {
    final sequence = snapshot.sequence;
    if (!stateUnverified && sequence == _reconciledSequence) {
      return false;
    }
    _reconciledSequence = sequence;
    _reconcileOnly = true;
    final sessions = snapshot.sessions;
    final unknownApp = packageName == null
        ? null
        : sessions
              .where(
                (item) =>
                    item.session.deviceId == deviceId &&
                    item.session.packageName == packageName &&
                    item.session.launchOutcome == .unknown,
              )
              .firstOrNull;
    _visibilityEpoch++;
    if (unknownApp != null) {
      showUnknownAppLaunch(unknownApp.toView());
      return true;
    }
    final recovered = sessions
        .where(
          (item) => item.session.sessionId == sessionId && sessionId.isNotEmpty,
        )
        .firstOrNull;
    _connecting = false;
    _paused = true;
    if (_visibility == _Visibility.resuming) _visibility = _Visibility.visible;
    _controlAvailable = false;
    if (recovered == null || !recovered.live) {
      if (_session case final previous?) _session = _withoutOutput(previous);
      _verification = _Verification.ended;
      _error = '无法恢复原来的画面。请先查看「当前活动」。';
    } else {
      final existing = recovered.toView();
      if (existing.session.status == .failed &&
          existing.session.qualityRetryable) {
        _failQuality(existing);
      } else if (_qualityRebuilding && !existing.session.qualityRebuilding) {
        updateSession(existing);
        if (existing.output case final receipt?) {
          output(receipt, verified: true);
        }
      } else {
        if (!_qualityRebuilding) _session = existing;
        if (existing.session.qualityRebuilding) {
          _beginQuality(existing);
        } else if (existing.outputRetained &&
            existing.output!.captureGeneration !=
                existing.session.captureGeneration) {
          _beginQuality(existing, target: existing.session.captureGeneration);
          updateSession(existing);
        }
      }
      _verification = _Verification.verified;
      _launch = _Launch.normal;
      if (!_qualityFailed) _error = null;
      _controlAvailable = false;
      _paused = true;
    }
    return true;
  }

  static (int, int) _generation(VideoSessionView view) =>
      (view.session.captureGeneration, view.session.generation);
  static (int, int) _outputGeneration(VideoOutputReceipt receipt) =>
      (receipt.captureGeneration, receipt.generation);
  static bool _before((int, int) incoming, (int, int) current) =>
      incoming.$1 < current.$1 ||
      (incoming.$1 == current.$1 && incoming.$2 < current.$2);

  bool _older((int, int) incoming) {
    final current = _session;
    return current != null &&
        (_before(incoming, _generation(current)) ||
            (current.output != null &&
                _before(incoming, _outputGeneration(current.output!))));
  }

  void _failQuality(VideoSessionView data) {
    final previous = _qualityOriginal ?? _session;
    _session = data.copyWith(output: data.output ?? previous?.output);
    _qualityRebuilding = false;
    _qualityFailed = true;
    _controlAvailable = false;
    _paused = true;
    _connecting = false;
    _error = failureCodeMessage(
      data.session.failureCode,
      fallback: '无法更改画面设置。请在「画面与控制」中重试。',
    );
    _errorCode = 'quality_rebuild_failed';
  }

  /// 已退役捕获或渲染器的错误不能终止当前逻辑窗口。
  bool acceptsFailure({
    required int captureGeneration,
    required int generation,
  }) =>
      !_older((captureGeneration, generation)) &&
      (!_qualityRebuilding || captureGeneration >= (_qualityTarget ?? 0));

  void _beginQuality(VideoSessionView data, {int? target}) {
    final proposed = target ?? data.session.qualityRebuildTarget;
    if (_qualityRebuilding) {
      if (proposed != null && proposed > (_qualityTarget ?? 0)) {
        _qualityTarget = proposed;
        _qualityOutput = null;
        _qualityReady = null;
        _visibilityEpoch++;
        _bindingGeneration++;
      }
      return;
    }
    _qualityOriginal = _session;
    _qualityOutput = null;
    _qualityReady = null;
    _qualityTarget =
        proposed ?? ((_session?.session.captureGeneration ?? 0) + 1);
    _qualityRebuilding = true;
    _qualityFailed = false;
    _controlAvailable = false;
    _visibilityEpoch++;
    _bindingGeneration++;
    if (_visibility == _Visibility.resuming) _visibility = _Visibility.visible;
    _paused =
        _session?.session.status == .paused ||
        _visibility != _Visibility.visible ||
        _covered ||
        _lifecyclePaused;
    _error = null;
    _errorCode = null;
  }

  void _clearQuality() {
    _qualityRebuilding = false;
    _qualityFailed = false;
    _qualityOriginal = null;
    _qualityOutput = null;
    _qualityReady = null;
    _qualityTarget = null;
  }

  bool _completeQuality() {
    final ready = _qualityReady, receipt = _qualityOutput;
    if (ready == null ||
        receipt == null ||
        _generation(ready) != _outputGeneration(receipt)) {
      return false;
    }
    _session = ready.copyWith(
      session: ready.session.copyWith(
        qualityRebuilding: false,
        qualityRetryable: false,
        qualityRebuildOutcome: .applied,
      ),
      output: receipt,
    );
    _clearQuality();
    _connecting = false;
    _paused =
        ready.session.status == .paused ||
        _visibility != _Visibility.visible ||
        _covered ||
        _lifecyclePaused;
    _controlAvailable =
        _session!.hasDecodedFrame && ready.session.status == .streaming;
    _hasPresentedFrame = _hasPresentedFrame || _session!.hasDecodedFrame;
    _error = null;
    _errorCode = null;
    return true;
  }

  bool output(VideoOutputReceipt receipt, {bool verified = false}) {
    final current = _session;
    if (current == null ||
        receipt.sessionId != sessionId ||
        receipt.deviceId != current.deviceId ||
        _qualityFailed ||
        _older(_outputGeneration(receipt)) ||
        receipt.decodedReceipts < 1 ||
        receipt.decodedWidth < 1 ||
        receipt.decodedHeight < 1) {
      return false;
    }
    // 帧遥测只能更新已有绑定的尺寸，不能建立首帧或接管另一渲染器。
    if (!verified &&
        (!_hasPresentedFrame ||
            current.output == null ||
            !receipt.sameBinding(current.output!))) {
      return false;
    }
    if (_qualityRebuilding) {
      if (!verified ||
          receipt.captureGeneration < (_qualityTarget ?? 0) ||
          (_qualityOutput != null &&
              _before(
                _outputGeneration(receipt),
                _outputGeneration(_qualityOutput!),
              ))) {
        return false;
      }
      _qualityOutput = receipt;
      return _completeQuality();
    }
    if (receipt.captureGeneration != current.session.captureGeneration) {
      return false;
    }
    final next = current.copyWith(output: receipt);
    final firstFrame = !_hasPresentedFrame && verified && next.hasDecodedFrame;
    if (!_paused &&
        !firstFrame &&
        _error == null &&
        receipt.sameBinding(current.output ?? receipt) &&
        current.output != null &&
        receipt.decodedWidth == current.output!.decodedWidth &&
        receipt.decodedHeight == current.output!.decodedHeight) {
      return false;
    }
    _session = next;
    _controlAvailable =
        next.hasDecodedFrame && next.session.status == .streaming;
    if (firstFrame) {
      _hasPresentedFrame = true;
      _connecting = false;
    }
    if (next.hasDecodedFrame &&
        _visibility == _Visibility.visible &&
        !_covered &&
        !_lifecyclePaused) {
      _paused = next.session.status == .paused;
      _error = null;
    }
    return true;
  }

  /// 返回页面是否需要释放已持有的物理输入。
  bool updateSession(VideoSessionView data) {
    if (data.sessionId != sessionId || data.deviceId != _session?.deviceId) {
      return false;
    }
    final state = data.session, incoming = _generation(data);
    if (state.qualityRebuilding) {
      if (_older(incoming)) return false;
      final outgoing = binding;
      _beginQuality(data);
      // 新 renderer 与核心 ready 的两层代次一致前，保留最后核验的图像和尺寸。
      return outgoing != binding;
    }
    if (_qualityRebuilding) {
      final outcome = state.qualityRebuildOutcome;
      if (outcome == .restored &&
          _qualityOriginal?.output != null &&
          incoming == _outputGeneration(_qualityOriginal!.output!)) {
        _session = data.copyWith(
          output: data.output ?? _qualityOriginal!.output,
        );
        _clearQuality();
        _controlAvailable =
            _session!.hasDecodedFrame && state.status == .streaming;
        _paused =
            state.status == .paused ||
            _visibility != _Visibility.visible ||
            _covered ||
            _lifecyclePaused;
        return false;
      }
      if (outcome == .failed &&
          state.status == .failed &&
          state.qualityRetryable &&
          state.captureGeneration >=
              (_qualityOriginal?.session.captureGeneration ?? 0)) {
        _failQuality(data);
        return false;
      }
      if (outcome == .applied &&
          state.captureGeneration >= (_qualityTarget ?? 0) &&
          const {
            VideoSessionStatus.streaming,
            VideoSessionStatus.paused,
          }.contains(state.status)) {
        if (_qualityReady == null ||
            !_before(incoming, _generation(_qualityReady!))) {
          _qualityReady = data;
          _completeQuality();
        }
      }
      return false;
    }
    if (_older(incoming)) return false;
    if (state.status == .failed && state.qualityRetryable) {
      _failQuality(data);
      return true;
    }
    if (_qualityFailed) return false;
    final previousGeometryReady = imageGeometryReady;
    final previous = _session!;
    _session = data.copyWith(output: data.output ?? previous.output);
    final geometryChanged =
        (previousGeometryReady && !imageGeometryReady) ||
        (previous.session.width != null &&
            previous.session.width != state.width) ||
        (previous.session.height != null &&
            previous.session.height != state.height);
    if (geometryChanged) _bindingGeneration++;
    _controlAvailable = state.status == .streaming && _session!.hasDecodedFrame;
    if (_session!.hasDecodedFrame && imageGeometryReady && !state.paused) {
      _hasPresentedFrame = true;
      _connecting = false;
    }
    final release = state.status != .streaming;
    if (release) _paused = true;
    return release || geometryChanged;
  }

  void disconnect(String reason) {
    detachBinding();
    _connecting = false;
    _error = reason;
  }

  int beginPause() {
    _visibility = _Visibility.hidden;
    _paused = true;
    return ++_visibilityEpoch;
  }

  int beginResume() {
    _visibility = _Visibility.resuming;
    _paused = true;
    return ++_visibilityEpoch;
  }

  bool _receiptCurrent(int epoch, {required bool ownerCurrent}) =>
      !_exiting && ownerCurrent && !_covered && epoch == _visibilityEpoch;

  RemoteResumeResult completeResume(
    int epoch,
    VideoPlaybackReceipt? receipt, {
    required bool ownerCurrent,
  }) {
    if (!_receiptCurrent(epoch, ownerCurrent: ownerCurrent)) {
      return RemoteResumeResult.stale;
    }
    final current = _session;
    if (current == null ||
        _qualityRebuilding ||
        _qualityFailed ||
        (receipt != null &&
            (receipt.session.sessionId != sessionId ||
                receipt.session.deviceId != current.deviceId ||
                _older((
                  receipt.session.captureGeneration,
                  receipt.session.generation,
                ))))) {
      return RemoteResumeResult.stale;
    }
    if (receipt == null) return RemoteResumeResult.rendererNotReady;
    final next = current.copyWith(
      session: receipt.session,
      output: receipt.output,
    );
    if (!next.hasDecodedFrame ||
        receipt.output.paused ||
        receipt.session.status != .streaming) {
      return RemoteResumeResult.rendererNotReady;
    }
    _session = next;
    _paused = false;
    _visibility = _Visibility.visible;
    _connecting = false;
    _controlAvailable = true;
    _hasPresentedFrame = true;
    _error = null;
    return RemoteResumeResult.ready;
  }

  void revokeControl() => _controlAvailable = false;

  void leave() {
    _exiting = true;
    invalidateStart();
  }

  void phoneMoveFailed(String reason) {
    _exiting = false;
    failOperation(reason);
  }

  /// 队列用捕获的绑定判断准入，包含未知应用打开将存活会话替换成记录后仍需排空的清理。
  bool admitsQueuedInput(
    RemoteBinding captured,
    ControlAction action, {
    required bool foreground,
    required bool ownerCurrent,
  }) {
    final cleanup = action.isRelease;
    final detached = cleanup && _detachedCleanupBindings.contains(captured);
    if ((!cleanup &&
            (!_controlAvailable || _qualityRebuilding || _qualityFailed)) ||
        captured.$1.isEmpty ||
        (captured.$1 != sessionId && !detached) ||
        (!cleanup && captured.$2 != _bindingGeneration)) {
      return false;
    }
    final newInput = action.isInput && !action.isRelease;
    return !newInput ||
        canSendInput(foreground: foreground, ownerCurrent: ownerCurrent);
  }
}
