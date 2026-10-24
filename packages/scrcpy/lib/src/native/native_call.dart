import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../models.dart';

Future<T> nativeScrcpyCall<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error) {
    if (error is ScrcpyException) rethrow;
    final message = switch (error) {
      String message => message,
      AnyhowException(:final message) => message,
      _ => error.toString(),
    };
    final failure = RegExp(
      r'^([a-z][a-z0-9_]*):\s*(.*)$',
      dotAll: true,
    ).firstMatch(message);
    throw ScrcpyException(
      failure?.group(1) ?? 'native_scrcpy',
      failure?.group(2) ?? '原生捕获操作未完成。',
    );
  }
}
