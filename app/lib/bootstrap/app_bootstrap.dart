import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:io';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/application_session.dart';
import 'package:scrcpy_connect/services/platform/diagnostic_log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/services/media/outgoing_media_directory.dart';

/// 全部启动配置成功前由 bootstrap 拥有应用依赖，返回依赖后交给 provider scope。
Future<AppDependencies> bootstrapApplication({
  Future<AppDependencies> Function()? createDependencies,
  DiagnosticLog? diagnostics,
  Future<Directory> Function()? prepareOutgoingDirectory,
}) async {
  final dependencies =
      await (createDependencies ?? () => _createDependencies(diagnostics))();
  try {
    final outgoing =
        await (prepareOutgoingDirectory ?? outgoingMediaDirectory)();
    await dependencies.request(ApplicationCommand.mediaCacheConfigure.wire, {
      'outgoingDirectory': outgoing.path,
    });
    return dependencies;
  } catch (error, stack) {
    try {
      await dependencies.close?.call();
    } catch (_) {
      // 即使清理失败，也保留最初可操作的启动错误。
    }
    Error.throwWithStackTrace(error, stack);
  }
}

Future<AppDependencies> _createDependencies(DiagnosticLog? diagnostics) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final session = await ApplicationSession.initialize(
    dataDirectory: await directory.resolveSymbolicLinks(),
    diagnostics: diagnostics,
  );
  Future<Json> invoke(Future<Json> Function() operation) async {
    try {
      return await operation();
    } on ApplicationCommandException catch (error) {
      throw RequestFailure(error.code, error.message, error.details);
    }
  }

  return AppDependencies(
    bindClipboardAdmission: session.bindClipboardAdmission,
    execute: (command, params) =>
        invoke(() => session.execute(command, params)),
    diagnostics: diagnostics,
    request: (command, [params = const {}]) =>
        invoke(() => session.request(command, params)),
    events: session.events,
    close: session.dispose,
  );
}
