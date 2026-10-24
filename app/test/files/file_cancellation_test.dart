import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'completed operations unregister while active work still cancels once',
    () async {
      final cancellation = FileCancellation();
      var completedCalls = 0, activeCalls = 0;
      for (var operation = 0; operation < 10000; operation++) {
        final remove = cancellation.onCancel(() => completedCalls++);
        remove();
        remove();
      }
      final removeActive = cancellation.onCancel(() => activeCalls++);
      cancellation.cancel();
      await cancellation.whenCancelled;
      cancellation.cancel();
      removeActive();
      expect(completedCalls, 0);
      expect(activeCalls, 1);
      expect(
        cancellation.check,
        throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
    },
  );

  test('work admitted after cancellation is cancelled immediately', () {
    final cancellation = FileCancellation()..cancel();
    var calls = 0;
    final remove = cancellation.onCancel(() => calls++);
    expect(calls, 1);
    remove();
    cancellation.cancel();
    expect(calls, 1);
  });
}
