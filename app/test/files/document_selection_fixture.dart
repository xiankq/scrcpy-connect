import 'package:adb/adb.dart';
import 'package:scrcpy_connect/services/file_document_service.dart';
import 'package:scrcpy_connect/stores/file_document_store.dart';

import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/file_selection_store.dart';

FileSelectionStore fakeDocumentSelections(
  Future<Json> Function(String, Json) platform,
) {
  late final FileSelectionStore selections;
  Future<void> select(Json plan) async {
    final id = plan['operationId'] as String;
    try {
      selections.complete(
        id,
        await platform('documents.platform.picker', plan),
      );
    } catch (error) {
      selections.complete(id, {
        'status': 'failed',
        'code': error is RequestFailure ? error.code : 'selection_failed',
        'message': '$error',
      });
    }
  }

  selections = FileSelectionStore((plan) => unawaited(select(plan)));
  return selections;
}

FileSelectionStore fakeDesktopSelections(
  Future<String?> Function(String, String) pick,
) => fakeDocumentSelections((_, plan) async {
  final path = await pick(plan['name'] as String, plan['kind'] as String);
  return path == null
      ? {'status': 'cancelled'}
      : {'status': 'selected', 'destination': path};
});

FileDocumentService testDocuments({
  required Future<LocalFiles> Function() files,
  required DocumentsRequest platform,
  FileDocumentStore? sources,
  bool Function()? isDisposed,
  void Function(DocumentsJson)? onConflictChanged,
  DocumentLimits limits = const DocumentLimits(),
}) => FileDocumentService(
  files: files,
  platform: platform,
  sources: sources,
  isDisposed: isDisposed,
  onConflictChanged: onConflictChanged,
  limits: limits,
  selections: fakeDocumentSelections(platform),
);
