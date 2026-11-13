import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/document_operation_notifier.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/widgets/documents/document_picker.dart';

/// 视图只呈现已认领的系统选择请求，回执始终交给发起时的操作。
void useDocumentPicker(WidgetRef ref, DocumentOperationNotifier operation) {
  final events = ref.watch(runtimeEventsProvider);
  useEffect(() {
    final subscription = events.listen((event) {
      if (event.data case DocumentSelectionRequested(:final request)) {
        final reply = operation.claimSelection(request);
        if (reply == null) return;
        unawaited(() async {
          DocumentSelectionResult result;
          try {
            result = await DocumentPicker.choose(request);
          } catch (failure) {
            result = DocumentSelectionFailed(
              failure is RequestFailure ? failure.code : 'selection_failed',
              '$failure',
            );
          }
          reply(result);
        }());
      }
    });
    return () => unawaited(subscription.cancel());
  }, [events, operation]);
}
