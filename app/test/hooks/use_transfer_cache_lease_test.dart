import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';

void main() {
  testWidgets('换源及离页后的迟到传输租约仍由原内容能力释放', (tester) async {
    final previous = _Content();
    final replacement = _Content();
    final oldLease = Completer<String>();
    final newLease = Completer<String>();
    final container = ProviderContainer(
      overrides: [
        contentReaderProvider.overrideWithValue(previous),
        transferCacheLeaseProvider.overrideWithValue((_) => oldLease.future),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Lease()),
      ),
    );
    container.updateOverrides([
      contentReaderProvider.overrideWithValue(replacement),
      transferCacheLeaseProvider.overrideWithValue((_) => newLease.future),
    ]);
    await tester.pump();
    oldLease.complete('old-lease');
    await tester.pumpAndSettle();
    expect(previous.released, ['old-lease']);
    expect(replacement.released, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    newLease.complete('new-lease');
    await tester.pumpAndSettle();
    expect(previous.released, ['old-lease']);
    expect(replacement.released, ['new-lease']);
    expect(tester.takeException(), isNull);
  });
}

class _Lease extends HookConsumerWidget {
  const _Lease();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lease = useTransferCacheLease(ref, 'task');
    return Text(lease.data ?? 'loading');
  }
}

class _Content implements ContentReader {
  final released = <String>[];
  @override
  Future<void> releaseLease(String leaseId) async => released.add(leaseId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
