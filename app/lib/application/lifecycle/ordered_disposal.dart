import 'dart:async';

/// 按顺序释放独立资源；调用方负责在开始释放前撤销新的活动准入。
final class OrderedDisposal {
  OrderedDisposal(this._steps);

  final List<Future<void> Function()> _steps;
  final _completed = <int>{};
  Future<void>? _running;

  Future<void> run() => _running ??= _release().whenComplete(() {
    _running = null;
  });

  Future<void> _release() async {
    Object? failure;
    StackTrace? failureStack;
    for (var index = 0; index < _steps.length; index++) {
      if (_completed.contains(index)) continue;
      try {
        await _steps[index]();
        _completed.add(index);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}
