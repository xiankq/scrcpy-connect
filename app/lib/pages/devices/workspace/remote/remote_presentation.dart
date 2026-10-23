typedef RemoteData = Map<String, dynamic>;
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

/// Presentation authority for one remote route. IO and widget lifetimes stay
/// with the page; binding changes, receipt fencing and input permission live
/// here so every caller uses the same transitions.
class RemotePresentation {
  RemoteData? _session;
  String? _error;
  String? _errorCode;
  bool _connecting = true;
  bool _paused = false;
  bool _exiting = false;
  bool _initialActionApplied = false;
  bool _lifecyclePaused = false;
  bool _covered = false;
  bool _controlAvailable = false;
  bool _qualityRebuilding = false;
  bool _qualityFailed = false;
  RemoteData? _qualityOriginal;
  RemoteData? _qualityOutput;
  RemoteData? _qualityReady;
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
  bool get paused => _paused;
  bool get exiting => _exiting;
  bool get lifecyclePaused => _lifecyclePaused;
  bool get covered => _covered;
  RemoteData? get session =>
      _session == null ? null : Map.unmodifiable(_session!);
  String get sessionId =>
      (_session?['sessionId'] ?? _session?['id'] ?? '').toString();
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

  double _dimension(String decoded, String capture) =>
      (num.tryParse('${_session?[decoded]}') ??
              num.tryParse('${_session?[capture]}') ??
              0)
          .toDouble();

  double get imageWidth => _dimension('decodedWidth', 'width');
  double get imageHeight => _dimension('decodedHeight', 'height');

  bool get imageGeometryReady {
    final width = num.tryParse('${_session?['width']}') ?? 0;
    final height = num.tryParse('${_session?['height']}') ?? 0;
    return width <= 0 ||
        height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0 ||
        (width / height - imageWidth / imageHeight).abs() < .005;
  }

  void checking() => _connecting = true;

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

  void retainUnverifiedStart(RemoteData result) {
    if (sessionId.isNotEmpty) return;
    _session = {...result}..remove('textureId');
    _verification = _Verification.pending;
    _connecting = false;
    _error = '会话结果尚待核验，请重新检查。';
  }

  void bindStart(
    RemoteData result, {
    required bool retained,
    required bool recoveringConnection,
    required bool submittedAppStart,
  }) {
    _session = _retainedImage(result);
    if (recoveringConnection) _reconcileOnly = false;
    _controlAvailable =
        sessionId.isNotEmpty &&
        result['textureId'] != null &&
        result['outputRetained'] != true;
    _visibility = _Visibility.visible;
    _lifecyclePaused = false;
    _connecting = retained && result['textureId'] != null;
    _paused = result['status'] == 'paused';
    if (result['qualityRebuilding'] == true) _beginQuality(result);
    if (result['outputRetained'] == true &&
        result['captureGeneration'] is int) {
      _beginQuality({
        ...result,
        'qualityRebuildTarget': result['captureGeneration'],
      });
      if (result['qualityRebuilding'] == false) updateSession(result);
    }
    if (result['status'] == 'failed' && result['qualityRetryable'] == true) {
      _failQuality(result);
    }
    if (result['textureId'] == null) {
      if (submittedAppStart) _launch = _Launch.unknown;
      _error = result['reason']?.toString() ?? '尚未获得设备的实时画面。请检查设备连接和视频能力。';
    }
  }

  void failStart(
    String reason,
    String? code, {
    required bool submittedAppStart,
    required RemoteData details,
  }) {
    _connecting = false;
    _error = reason;
    _errorCode = code;
    // Only explicit pre-submission rejections establish that retry is safe.
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
        }.contains(code)) {
      _launch = _Launch.unknown;
      if (details['sessionId'] is String) _session = details;
    }
  }

  void showUnknownAppLaunch(RemoteData record) {
    _session = {...record}..remove('textureId');
    _launch = _Launch.unknown;
    _verification = _Verification.verified;
    _connecting = false;
    _controlAvailable = false;
    _errorCode = 'app_launch_unknown';
    _error = '应用打开请求的结果未知，应用可能已打开或迁移。请在手机核对；检查不会再次打开应用。';
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

  int beginReconciliation({RemoteData? initialSession, String? reason}) {
    if (initialSession != null) _session = initialSession;
    _stateEpoch++;
    _visibilityEpoch++;
    invalidateStart();
    // Freeze before the page captures releases for the outgoing binding.
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

  /// False means a duplicate snapshot; no capture or focus effect is needed.
  bool reconcile(
    RemoteData snapshot, {
    required String? packageName,
    required Object? deviceId,
  }) {
    final sequence = snapshot['sequence'];
    if (!stateUnverified &&
        sequence is int &&
        sequence == _reconciledSequence) {
      return false;
    }
    _reconciledSequence = sequence is int ? sequence : null;
    _reconcileOnly = true;
    final sessions = (snapshot['sessions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    final unknownApp = packageName == null
        ? null
        : sessions
              .where(
                (item) =>
                    item['deviceId'] == deviceId &&
                    item['packageName'] == packageName &&
                    item['launchOutcome'] == 'unknown',
              )
              .firstOrNull;
    _visibilityEpoch++;
    if (unknownApp != null) {
      showUnknownAppLaunch(unknownApp);
      return true;
    }
    final existing = sessions
        .where(
          (item) =>
              (item['sessionId'] ?? item['id'] ?? '').toString() == sessionId &&
              sessionId.isNotEmpty,
        )
        .firstOrNull;
    _connecting = false;
    _paused = true;
    if (_visibility == _Visibility.resuming) _visibility = _Visibility.visible;
    _controlAvailable = false;
    if (existing == null ||
        (const ['stopped', 'failed', 'error'].contains(existing['status']) &&
            !(existing['status'] == 'failed' &&
                existing['qualityRetryable'] == true))) {
      _session = {...?_session}..remove('textureId');
      _verification = _Verification.ended;
      _error = '原会话已结束或无法核验。请检查当前活动，不会自动创建新窗口。';
    } else {
      if (existing['status'] == 'failed' &&
          existing['qualityRetryable'] == true) {
        _failQuality(_retainedImage(existing));
      } else if (_qualityRebuilding && existing['qualityRebuilding'] == false) {
        updateSession(existing);
        output(
          existing,
          verified:
              existing['firstFrameDecoded'] == true &&
              existing['evidence'] == 'media_codec.snapshot',
        );
      } else {
        if (!_qualityRebuilding) _session = _retainedImage(existing);
        if (existing['qualityRebuilding'] == true) {
          _beginQuality(existing);
        } else if (existing['outputRetained'] == true &&
            existing['captureGeneration'] is int) {
          _beginQuality({
            ...existing,
            'qualityRebuildTarget': existing['captureGeneration'],
          });
          updateSession(existing);
        }
      }
      _verification = _Verification.verified;
      if (!_qualityFailed) _error = null;
      _controlAvailable = false;
      _paused = true;
    }
    return true;
  }

  static (int, int)? _generation(RemoteData? data) {
    final capture = data?['captureGeneration'];
    final renderer = data?['rendererGeneration'] ?? data?['generation'];
    return capture is int && renderer is int ? (capture, renderer) : null;
  }

  static (int, int)? _outputGeneration(RemoteData? data) {
    final capture = data?['outputCaptureGeneration'];
    final renderer = data?['outputGeneration'];
    return capture is int && renderer is int
        ? (capture, renderer)
        : _generation(data);
  }

  static RemoteData _retainedImage(RemoteData data) {
    if (data['outputRetained'] != true) return data;
    // Input remains blocked. Size this placeholder by the retained texture,
    // rather than stretching its old pixels to the new capture's dimensions.
    return {
      ...data,
      if (data['decodedWidth'] is num && (data['decodedWidth'] as num) > 0)
        'width': data['decodedWidth'],
      if (data['decodedHeight'] is num && (data['decodedHeight'] as num) > 0)
        'height': data['decodedHeight'],
    };
  }

  void _failQuality(RemoteData data) {
    _session = data;
    _qualityRebuilding = false;
    _qualityFailed = true;
    _controlAvailable = false;
    _paused = true;
    _connecting = false;
    _error = data['reason']?.toString() ?? '画面调整未完成，请在画面设置中重试。';
    _errorCode = 'quality_rebuild_failed';
  }

  bool _older(RemoteData data) {
    final incoming = _generation(data);
    final current = _generation(_session);
    return incoming != null &&
        current != null &&
        (incoming.$1 < current.$1 ||
            (incoming.$1 == current.$1 && incoming.$2 < current.$2));
  }

  /// Errors from a retired capture cannot end this logical window.
  bool acceptsFailure(RemoteData data) {
    if (_older(data)) return false;
    if (!_qualityRebuilding) return true;
    final incoming = _generation(data);
    return incoming != null && incoming.$1 >= (_qualityTarget ?? 0);
  }

  void _beginQuality(RemoteData data) {
    if (_qualityRebuilding) {
      final target = data['qualityRebuildTarget'];
      if (target is int && target > (_qualityTarget ?? 0)) {
        _qualityTarget = target;
        _qualityOutput = null;
        _qualityReady = null;
        _visibilityEpoch++;
        _bindingGeneration++;
      }
      return;
    }
    _qualityOriginal = {...?_session};
    _qualityOutput = null;
    _qualityReady = null;
    _qualityTarget =
        data['qualityRebuildTarget'] as int? ??
        ((_generation(_session)?.$1 ?? 0) + 1);
    _qualityRebuilding = true;
    _qualityFailed = false;
    _controlAvailable = false;
    _visibilityEpoch++;
    _bindingGeneration++;
    if (_visibility == _Visibility.resuming) _visibility = _Visibility.visible;
    _paused =
        _session?['status'] == 'paused' ||
        _visibility != _Visibility.visible ||
        _covered ||
        _lifecyclePaused;
    _error = null;
    _errorCode = null;
  }

  bool _completeQuality() {
    final ready = _qualityReady;
    final output = _qualityOutput;
    if (ready == null ||
        output == null ||
        _generation(ready) != _outputGeneration(output)) {
      return false;
    }
    _session = {
      ...?_qualityOriginal,
      ...ready,
      ...output,
      'qualityRebuilding': false,
      'qualityRetryable': false,
      'qualityRebuildOutcome': 'applied',
      'captureGeneration': _generation(ready)!.$1,
      'rendererGeneration': _generation(ready)!.$2,
      'generation': _generation(ready)!.$2,
      'status': ready['status'],
      'outputRetained': false,
    };
    _qualityRebuilding = false;
    _qualityFailed = false;
    _qualityOriginal = null;
    _qualityOutput = null;
    _qualityReady = null;
    _qualityTarget = null;
    _connecting = false;
    _paused =
        ready['status'] == 'paused' ||
        _visibility != _Visibility.visible ||
        _covered ||
        _lifecyclePaused;
    _controlAvailable =
        _session?['textureId'] != null && ready['status'] == 'streaming';
    _error = null;
    _errorCode = null;
    return true;
  }

  bool output(RemoteData data, {bool verified = false}) {
    if (_qualityFailed || _older(data)) return false;
    if (_qualityRebuilding) {
      final incoming = _outputGeneration(data);
      if (!verified ||
          data['firstFrameDecoded'] != true ||
          data['evidence'] != 'media_codec.snapshot' ||
          data['textureId'] == null ||
          data['outputRetained'] == true ||
          incoming == null ||
          incoming.$1 < (_qualityTarget ?? 0)) {
        return false;
      }
      _qualityOutput = data;
      return _completeQuality();
    }
    final next = {...?_session, ...data};
    if (!_paused &&
        _error == null &&
        _generation(next) == _generation(_session) &&
        next['width'] == _session?['width'] &&
        next['height'] == _session?['height'] &&
        next['decodedWidth'] == _session?['decodedWidth'] &&
        next['decodedHeight'] == _session?['decodedHeight'] &&
        next['textureId'] == _session?['textureId']) {
      return false;
    }
    _session = next;
    if (next['textureId'] != null &&
        _visibility == _Visibility.visible &&
        !_covered) {
      _paused = false;
      _error = null;
    }
    return true;
  }

  /// Returns whether the page must release its held physical input.
  bool updateSession(RemoteData data) {
    if (data['qualityRebuilding'] == true) {
      if (_older(data)) return false;
      final outgoing = binding;
      _beginQuality(data);
      // Keep the last verified image and its dimensions until the new local
      // renderer and core ready receipt agree on both generations.
      _session = {...?_session, 'qualityRebuilding': true};
      return outgoing != binding;
    }
    if (_qualityRebuilding) {
      if (data['qualityRebuilding'] != false) return false;
      final incoming = _generation(data);
      final outcome = data['qualityRebuildOutcome'];
      if (outcome == 'restored' &&
          incoming != null &&
          incoming == _outputGeneration(_qualityOriginal)) {
        _session = {...?_qualityOriginal, ...data, 'qualityRetryable': false};
        _qualityRebuilding = false;
        _qualityFailed = false;
        _controlAvailable =
            _session?['textureId'] != null && data['status'] == 'streaming';
        _paused =
            data['status'] == 'paused' ||
            _visibility != _Visibility.visible ||
            _covered ||
            _lifecyclePaused;
        _qualityOriginal = null;
        _qualityOutput = null;
        _qualityReady = null;
        _qualityTarget = null;
        return false;
      }
      if (outcome == 'failed' &&
          data['status'] == 'failed' &&
          data['qualityRetryable'] == true &&
          (incoming == null ||
              incoming.$1 >= (_generation(_qualityOriginal)?.$1 ?? 0))) {
        _failQuality({...?_qualityOriginal, ...data});
        return false;
      }
      if (outcome == 'applied' &&
          incoming != null &&
          incoming.$1 >= (_qualityTarget ?? 0) &&
          const ['streaming', 'paused'].contains(data['status'])) {
        _qualityReady = data;
        _completeQuality();
      }
      return false;
    }
    if (_older(data)) return false;
    if (data['status'] == 'failed' && data['qualityRetryable'] == true) {
      _failQuality({...?_session, ...data});
      return true;
    }
    if (_qualityFailed) return false;
    final previousGeometryReady = imageGeometryReady;
    _session = {...?_session, ...data};
    final geometryChanged = previousGeometryReady && !imageGeometryReady;
    if (geometryChanged) _bindingGeneration++;
    if (data['status'] == 'streaming' && data['connected'] != false) {
      _controlAvailable = true;
    }
    if (const [
          'connecting',
          'reconnecting',
          'stopped',
        ].contains(data['status']) ||
        data['connected'] == false) {
      _controlAvailable = false;
    }
    final release =
        const [
          'paused',
          'connecting',
          'reconnecting',
          'stopped',
        ].contains(data['status']) ||
        data['connected'] == false;
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
    RemoteData receipt, {
    required bool ownerCurrent,
  }) {
    if (!_receiptCurrent(epoch, ownerCurrent: ownerCurrent)) {
      return RemoteResumeResult.stale;
    }
    if (_qualityRebuilding || _qualityFailed || _older(receipt)) {
      return RemoteResumeResult.stale;
    }
    if (receipt['firstFrameDecoded'] != true ||
        receipt['evidence'] != 'media_codec.snapshot') {
      return RemoteResumeResult.rendererNotReady;
    }
    _session = {...?_session, ...receipt};
    _paused = false;
    _visibility = _Visibility.visible;
    _connecting = false;
    _controlAvailable = _session?['textureId'] != null;
    _error = null;
    return RemoteResumeResult.ready;
  }

  void revokeControl() => _controlAvailable = false;

  void leave() {
    _exiting = true;
    invalidateStart();
  }

  /// Queue admission uses the captured binding, including cleanup that may
  /// drain after an unknown app launch replaced the live session with a record.
  bool admitsQueuedInput(
    RemoteBinding captured,
    String command,
    RemoteData params, {
    required bool foreground,
    required bool ownerCurrent,
  }) {
    final cleanup =
        (command == 'session.key' && params['action'] == 'up') ||
        (command == 'session.touch' &&
            const ['up', 'cancel'].contains(params['action']));
    final detached = cleanup && _detachedCleanupBindings.contains(captured);
    if ((!cleanup &&
            (!_controlAvailable || _qualityRebuilding || _qualityFailed)) ||
        captured.$1.isEmpty ||
        (captured.$1 != sessionId && !detached) ||
        (!cleanup && captured.$2 != _bindingGeneration)) {
      return false;
    }
    final newInput =
        command == 'session.text' ||
        command == 'session.scroll' ||
        (command == 'session.key' && params['action'] == 'down') ||
        (command == 'session.touch' &&
            const ['down', 'move', 'hover'].contains(params['action']));
    return !newInput ||
        canSendInput(foreground: foreground, ownerCurrent: ownerCurrent);
  }
}
