import 'dart:io';

import 'package:scrcpy_connect/bootstrap/app_runtime.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/core/application/app_dependencies.dart';
import 'package:scrcpy_connect/core/files/file_local_directories.dart';

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
    await dependencies.cache.configure(outgoingDirectory: outgoing.path);
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
  final session = await AppRuntime.initialize(
    dataDirectory: await directory.resolveSymbolicLinks(),
    diagnostics: diagnostics,
  );
  return AppDependencies(
    content: session.content,
    clipboard: session.clipboard,
    control: session.control,
    remoteAudio: session.remoteAudio,
    videoQuality: session.videoQuality,
    screenshots: session.screenshots,
    displays: session.displays,
    activities: session.activities,
    reconcileState: session.reconcileState,
    background: session.background,
    devices: session.deviceManagement,
    connections: session.connections,
    setup: session.setup,
    inspection: session.inspection,
    assessment: session.assessment,
    observation: session.observation,
    calls: session.calls,
    notifications: session.notifications,
    fileSearch: session.fileSearch,
    directories: session.directories,
    fileMutations: session.fileMutations,
    fileTransfers: session.fileTransfers,
    incomingShares: session.incomingShares,
    documents: session.documents,
    gallery: session.gallery,
    apps: session.apps,
    wake: session,
    applicationInfo: session.applicationInfo,
    identity: session.identity,
    metadata: session.metadata,
    settings: session.settings,
    cache: session.cache,
    acquireTransferCacheLease: session.acquireTransferCacheLease,
    completeDocumentSelection: session.completeDocumentSelection,
    setVisible: session.setVisible,
    diagnostics: diagnostics,
    videos: session.videos,
    events: session.events,
    close: session.dispose,
  );
}
