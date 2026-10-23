import 'dart:io';

import 'package:device_runtime/device_runtime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/media_cache_directory.dart';

/// Bootstrap owns the transport until all startup configuration succeeds.
/// The returned dependencies transfer that ownership to the provider scope.
Future<AppDependencies> bootstrapApplication({
  Future<AppDependencies> Function()? initializeTransport,
  DiagnosticLog? diagnostics,
  Future<Directory> Function()? prepareOutgoingDirectory,
}) async {
  final dependencies =
      await (initializeTransport ?? () => _initializeTransport(diagnostics))();
  try {
    final outgoing =
        await (prepareOutgoingDirectory ?? outgoingMediaDirectory)();
    await dependencies.request(InteropCommand.mediaCacheConfigure.wire, {
      'outgoingDirectory': outgoing.path,
    });
    return dependencies;
  } catch (error, stack) {
    try {
      await dependencies.close?.call();
    } catch (_) {
      // Keep the actionable startup failure even if detaching also fails.
    }
    Error.throwWithStackTrace(error, stack);
  }
}

Future<AppDependencies> _initializeTransport(DiagnosticLog? diagnostics) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final bridge = await DeviceRuntime.initialize(
    dataDirectory: await directory.resolveSymbolicLinks(),
    diagnostics: diagnostics,
  );
  return AppDependencies(
    diagnostics: diagnostics,
    request: (command, [params = const {}]) async {
      try {
        return await bridge.request(command, params);
      } on InteropException catch (error) {
        throw RequestFailure(error.code, error.message, error.details);
      }
    },
    events: bridge.events,
    close: bridge.dispose,
  );
}
