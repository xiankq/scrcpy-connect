import 'dart:async';
import 'dart:isolate';

import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// One existing capability borrowed by another engine in the same isolate group.
final class WindowIsolateOwner<T> {
  WindowIsolateOwner(T capability) {
    _requests.listen((message) async {
      if (message is _WindowCall<T>) {
        await message.run(capability);
      }
    });
  }

  final _requests = ReceivePort();
  SendPort get port => _requests.sendPort;

  void dispose() => _requests.close();
}

final class WindowIsolatePort<T> {
  const WindowIsolatePort(this.port);
  final SendPort port;

  Future<R> call<P, R>(FutureOr<R> Function(T, P) operation, P input) async {
    final reply = ReceivePort();
    try {
      port.send(_WindowCallOf(operation, input, reply.sendPort));
      final result = await reply.first.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw const RequestFailure(
          'window_unavailable',
          '远控窗口已失去响应，请切回工作台重试。',
        ),
      );
      return switch (result) {
        _WindowValue<R>(:final value) => value,
        _WindowFailure(:final error, :final stack) => Error.throwWithStackTrace(
          error,
          stack,
        ),
        _ => throw StateError('远控窗口返回了不匹配的结果。'),
      };
    } finally {
      reply.close();
    }
  }
}

sealed class _WindowCall<T> {
  Future<void> run(T capability);
}

final class _WindowCallOf<T, P, R> implements _WindowCall<T> {
  const _WindowCallOf(this.operation, this.input, this.reply);
  final FutureOr<R> Function(T, P) operation;
  final P input;
  final SendPort reply;

  @override
  Future<void> run(T capability) async {
    try {
      reply.send(_WindowValue<R>(await operation(capability, input)));
    } catch (error, stack) {
      reply.send(_WindowFailure(error, stack));
    }
  }
}

final class _WindowValue<T> {
  const _WindowValue(this.value);
  final T value;
}

final class _WindowFailure {
  const _WindowFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}
