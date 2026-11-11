import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/services/clipboard_sync.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

part 'clipboard_sync_store.g.dart';

@Riverpod(keepAlive: true)
ClipboardSync clipboardSync(Ref ref) {
  final controller = ref.watch(appStoreProvider.notifier);
  final coordinator = ClipboardSync(controller);
  ref.listen(
    appStoreProvider.select(
      (state) => (
        state.settings,
        state.devices,
        state.focusedDeviceId,
        state.reconciliationPending,
        state.reconciliationError,
      ),
    ),
    (_, next) => coordinator.configure(),
  );
  ref.onDispose(coordinator.dispose);
  Future<void>.microtask(coordinator.configure);
  return coordinator;
}
