import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/files/models/document_outcome.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';

sealed class DocumentEvent extends AppEvent {
  const DocumentEvent();
}

final class DocumentSelectionRequested extends DocumentEvent {
  const DocumentSelectionRequested(this.request);
  final DocumentSelectionRequest request;

  @override
  String get type => 'documents.selection.requested';
}

final class DocumentDeliveryChanged extends DocumentEvent {
  const DocumentDeliveryChanged(this.source);
  final DocumentSource source;

  @override
  String get type => 'delivery.changed';
}

final class DocumentConflictChanged extends DocumentEvent {
  const DocumentConflictChanged(this.operationId, this.pending);
  final String operationId;
  final DocumentConflict? pending;

  @override
  String get type => 'documents.conflict.changed';
}
