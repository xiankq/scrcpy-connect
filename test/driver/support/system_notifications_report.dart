/// 宿主核验真实 Android 记录、SystemUI 点击及清理；协调器单测覆盖未尝试远端命令，本真实应用运行核验来源/会话及被控前台结果。
///
///
void validateSystemNotificationsReport(
  Map<String, dynamic> report, {
  required String runId,
  required Map<String, dynamic>? osReceipt,
  required bool cleanupConfirmed,
}) {
  final ids = report['sourceNotificationIds'];
  if (report.containsKey('productAcceptanceComplete') ||
      report['systemNotificationsComplete'] != true ||
      report['fixtureRunId'] != runId ||
      ids is! List ||
      ids.length != 2 ||
      ids.any((id) => id is! String || id.isEmpty) ||
      ids.toSet().length != 2 ||
      [
        'permissionGranted',
        'automaticObservationLive',
        'realNotificationEventObserved',
        'exactSourceWithdrawalVerified',
        'notificationsPageOpened',
        'clickedSourceStillLive',
        'remoteSessionUnchanged',
        'fixtureCleanupAcknowledged',
      ].any((key) => report[key] != true)) {
    throw StateError(
      'The app did not complete scoped system notification acceptance.',
    );
  }
  final localIds = osReceipt?['localNotificationIds'];
  if (osReceipt == null ||
      osReceipt['runId'] != runId ||
      osReceipt['channel'] != 'remote_notifications' ||
      osReceipt['genericRecordCount'] != 2 ||
      osReceipt['sourceRecordCount'] != 2 ||
      localIds is! List ||
      localIds.length != 2 ||
      localIds.any((id) => id is! int || id < 100000 || id > 199999) ||
      localIds.toSet().length != 2 ||
      [
        'actualHome',
        'baselineEmpty',
        'genericContentOnly',
        'exactWithdrawal',
        'otherMirrorRetained',
        'foregroundServiceRetained',
        'actualSystemUiTap',
        'targetForegroundUnchanged',
        'ownedSourcesAbsent',
        'ownedMirrorsAbsent',
      ].any((key) => osReceipt[key] != true)) {
    throw StateError(
      'Independent Android system notification evidence is missing or inconsistent.',
    );
  }
  if (!cleanupConfirmed) {
    throw StateError(
      'Exact source and mirrored notification cleanup was not confirmed.',
    );
  }
}
