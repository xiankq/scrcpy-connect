import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/runtime_initialization.dart';

void main() {
  test('bridge retry reuses native bindings after later attachment failure', () async {
    var initialized = false;
    var bindingCalls = 0;
    var coreCalls = 0;
    final runtime = RuntimeInitialization(
      bindingsInitialized: () => initialized,
      initializeBindings: () async {
        if (initialized) throw StateError('Should not initialize twice');
        bindingCalls++;
        initialized = true;
      },
      initializeRuntime: (_) async {
        if (++coreCalls == 1) throw StateError('core attachment failed');
      },
    );
    await expectLater(runtime.attach('/private'), throwsStateError);
    await runtime.attach('/private');
    // A disposed UI bridge may attach once more without unloading native code.
    await runtime.attach('/private');
    expect(bindingCalls, 1);
    expect(coreCalls, 3);
  });

  test('simultaneous attachments share initialization and reject another identity root', () async {
    var initialized = false;
    var bindingCalls = 0;
    final gate = Completer<void>();
    final runtime = RuntimeInitialization(
      bindingsInitialized: () => initialized,
      initializeBindings: () async {
        bindingCalls++;
        await gate.future;
        initialized = true;
      },
      initializeRuntime: (_) async {},
    );
    final first = runtime.attach('/private');
    final second = runtime.attach('/private');
    expect(identical(first, second), true);
    await expectLater(
      runtime.attach('/different'),
      throwsA(
        isA<InteropException>().having(
          (e) => e.code,
          'code',
          'runtime_directory_mismatch',
        ),
      ),
    );
    gate.complete();
    await Future.wait([first, second]);
    expect(bindingCalls, 1);
  });
}
