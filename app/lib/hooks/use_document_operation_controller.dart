import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/files/document_operation_controller.dart';

DocumentOperationController useDocumentOperationController(
  AppController controller, {
  Json? exportSource,
}) {
  final operation = useMemoized(
    () => DocumentOperationController(
      request: controller.request,
      execute: controller.execute,
      events: controller.eventStream(),
      exportSource: exportSource,
    ),
    [
      controller,
      exportSource?['sourceId'],
      exportSource?['localPath'],
      exportSource?['kind'],
    ],
  );
  useListenable(operation);
  useEffect(() {
    if (exportSource != null) Future.microtask(operation.refresh);
    return operation.dispose;
  }, [operation]);
  return operation;
}
