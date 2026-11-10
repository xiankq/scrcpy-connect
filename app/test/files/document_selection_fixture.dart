import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/file_selection_store.dart';

FileSelectionStore fakeDocumentSelections(
  Future<Json> Function(String, Json) platform,
) {
  late final FileSelectionStore selections;
  selections = FileSelectionStore((plan) {
    unawaited(
      Future.sync(() => platform('documents.platform.picker', plan))
          .then(
            (result) =>
                selections.complete(plan['operationId'] as String, result),
          )
          .catchError(
            (Object error) =>
                selections.complete(plan['operationId'] as String, {
                  'status': 'failed',
                  'code': error is RequestFailure
                      ? error.code
                      : 'selection_failed',
                  'message': '$error',
                }),
          ),
    );
  });
  return selections;
}

FileSelectionStore fakeDesktopSelections(
  Future<String?> Function(String, String) pick,
) {
  return fakeDocumentSelections((_, plan) async {
    final path = await pick(plan['name'] as String, plan['kind'] as String);
    return path == null
        ? {'status': 'cancelled'}
        : {'status': 'selected', 'destination': path};
  });
}
