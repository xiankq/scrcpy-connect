import 'dart:async';
import 'dart:collection';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

export 'package:scrcpy_connect/core/events/models/app_event.dart'
    show RuntimeEvent;

/// 应用的唯一业务事件序列；水位对应 Dart 所有者已发布的状态。
/// 媒体帧及呈现遥测不改变业务版本，持续播放不会使快照饥饿。
final class RuntimeEvents {
  RuntimeEvents({
    required this.acceptState,
    required this.onState,
    required this.beforePublish,
    required this.afterState,
    required this.handlePlatform,
    required this.isDisposed,
    this.onLocalStateChanged,
  });

  final bool Function({required int sequence, required bool telemetry})
  acceptState;
  final void Function(RuntimeEvent) onState;
  final void Function(RuntimeEvent) beforePublish;
  final void Function(RuntimeEvent) afterState;
  final Future<void> Function(Map<String, dynamic>) handlePlatform;
  final bool Function() isDisposed;
  final void Function()? onLocalStateChanged;
  final _events = StreamController<RuntimeEvent>.broadcast();
  final _pending =
      ListQueue<({RuntimeEvent event, int sequence, bool telemetry})>();
  final _files = <StreamSubscription<AppEvent>>[];
  StreamSubscription<AppEvent>? _sharing;
  StreamSubscription<dynamic>? _platform;
  OrderedDisposal? _detaching;
  int _sequence = 0, _revision = 0;
  bool _closed = false, _attached = false, _publishing = false;
  bool get _active => !_closed && !isDisposed();
  ({int sequence, int revision}) get cursor =>
      (sequence: _sequence, revision: _revision);
  Stream<RuntimeEvent> get stream => _events.stream;

  Future<void> attach({
    required Iterable<Stream<AppEvent>> files,
    Stream<AppEvent>? sharing,
    Stream<dynamic>? platform,
  }) async {
    if (_attached || !_active) throw StateError('应用观察者不能重复附着。');
    _attached = true;
    for (final source in files) {
      attachFileEvents(source);
    }
    _sharing = sharing?.listen(publishEvent, onError: _error);
    _platform = platform?.listen((event) {
      if (!_active || event is! Map) return;
      unawaited(
        Future<void>.sync(
          () => handlePlatform(Map<String, dynamic>.from(event)),
        ).catchError((Object error, StackTrace stack) => _error(error, stack)),
      );
    }, onError: _error);
  }

  /// 按需创建的文件查询在开始工作前附着，仍使用唯一的事件序列与关闭所有者。
  void attachFileEvents(Stream<AppEvent> source) {
    if (!_active || _detaching != null) throw StateError('应用事件所有者已关闭。');
    _files.add(source.listen(publishEvent, onError: _error));
  }

  /// 业务状态先登记水位再通知策略；同步回调重入也不能逆序发布。
  void publishEvent(AppEvent event) {
    if (!_active) return;
    final telemetry = event.telemetry;
    final sequence = ++_sequence;
    final stamped = event.toApplicationEvent(sequence: sequence);
    if (!telemetry) _revision++;
    _pending.add((event: stamped, sequence: sequence, telemetry: telemetry));
    if (_publishing) return;
    _publishing = true;
    try {
      while (_pending.isNotEmpty && _active) {
        _deliver(_pending.removeFirst());
      }
    } finally {
      _publishing = false;
      if (!_active) _pending.clear();
    }
  }

  void _deliver(({RuntimeEvent event, int sequence, bool telemetry}) delivery) {
    final (:event, :sequence, :telemetry) = delivery;
    if (!telemetry) {
      try {
        onLocalStateChanged?.call();
      } catch (error, stack) {
        _error(error, stack);
      }
    }
    try {
      // 验收异常时不转发未经核验的状态，但仍须完成所有者的资源登记。
      if (acceptState(sequence: sequence, telemetry: telemetry) && _active) {
        _events.add(event);
      }
    } catch (error, stack) {
      _error(error, stack);
    }
    for (final observer in [onState, beforePublish, afterState]) {
      try {
        observer(event);
      } catch (error, stack) {
        // 观察失败不能撤销已经发生的业务事实，亦不能中断精确资源登记。
        _error(error, stack);
      }
    }
  }

  /// 呈现遥测与恢复回执不修改业务版本，也不重新触发设备策略。
  void emitEvent(AppEvent event) {
    if (_active) _events.add(event.toApplicationEvent());
  }

  void _error(Object error, StackTrace stack) {
    if (_active) _events.addError(error, stack);
  }

  Future<void> detach() {
    _detaching ??= OrderedDisposal([
      for (final subscription in _files) subscription.cancel,
      () async => await _sharing?.cancel(),
      () async => await _platform?.cancel(),
    ]);
    return _detaching!.run();
  }

  Future<void> close() {
    _closed = true;
    _pending.clear();
    return _events.close();
  }
}
