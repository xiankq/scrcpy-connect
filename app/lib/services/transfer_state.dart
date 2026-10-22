import 'package:scrcpy_connect/services/app_controller.dart';

Json transferView(AppController controller, Json task) {
  final matches = controller.snapshot().devices.where(
    (d) => d['id'] == task['deviceId'],
  );
  final name = matches.isEmpty
      ? value(task, 'deviceName', '被控设备')
      : deviceName(matches.first);
  final pulling = task['direction'] == 'pull';
  return {
    ...task,
    if (task['kind'] == 'directory' &&
        task['status'] == 'completed' &&
        task['treeVerified'] != true)
      'status': 'finalizing',
    if (task['kind'] == 'directory' &&
        task['status'] == 'completed' &&
        task['treeVerified'] == true &&
        task['canExport'] == false)
      'status': 'partial',
    'totalBytes': task['totalBytes'] ?? task['total'],
    'completedBytes': task['completedBytes'] ?? task['transferred'],
    'sourceLabel': task['sourceLabel'] ?? (pulling ? name : '本机'),
    'destinationLabel':
        task['destinationLabel'] ??
        (pulling
            ? task['destinationScope'] == 'privateCache'
                  ? '本机暂存'
                  : value(task, 'destination')
            : name),
    'localPath':
        pulling && task['status'] == 'completed' && task['canExport'] == true
        ? task['localPath'] ?? task['destination']
        : null,
  };
}

bool transferStatusHasIssue(String status) => [
  'failed',
  'partialFailure',
  'partial',
  'interrupted',
  'paused',
].contains(status);

/// Compact list copy: the row names the remote endpoint only, because the
/// staging destination is a details-level fact.
String transferListDirection(Json task, String deviceName) =>
    task['direction'] == 'push' ? '发送 · 本机 → $deviceName' : '接收 · $deviceName';

/// Detail copy keeps both endpoints visible, including the private staging
/// scope that decides whether a system save is still required.
String transferDetailDirection(Json task, String deviceName) {
  if (task['direction'] == 'push') {
    return '发送 · 本机 → $deviceName';
  }
  if (task['destinationScope'] == 'privateCache') {
    return '接收 · $deviceName → 本机暂存';
  }
  return '接收 · $deviceName → 本机';
}

String transferByteSummary(Json task) {
  final completed =
      num.tryParse('${task['completedBytes'] ?? task['transferred']}') ?? 0;
  final total = num.tryParse('${task['totalBytes'] ?? task['total']}');
  if ((total == null || total <= 0) && completed <= 0) return '';
  if (total == null || total <= 0) return bytes(completed);
  final percent = ((completed / total) * 100).clamp(0, 100).floor();
  return '${bytes(completed)} / ${bytes(total)} · $percent%';
}

String transferResultSize(Json task) {
  final completed =
      num.tryParse('${task['completedBytes'] ?? task['transferred']}') ?? 0;
  final total = num.tryParse('${task['totalBytes'] ?? task['total']}') ?? 0;
  final actual = completed > 0 ? completed : total;
  return actual > 0 ? bytes(actual) : '';
}

/// The status line is the row's single progress/result channel. Completed and
/// stopped rows carry their actual byte result; active rows additionally carry
/// the real percentage used by the progress bar.
String transferStatusDescription(Json task) {
  final status = value(task, 'status');
  final progress = transferByteSummary(task);
  switch (status) {
    case 'failed':
      final reason = value(task, 'error');
      return reason.isEmpty ? statusText(status) : '失败 · $reason';
    case 'interrupted':
      final reason = value(task, 'error', '连接中断，已完成部分保留');
      return '已中断 · $reason';
    case 'cancelled':
      return '已停止，已完成部分保留';
    case 'completed':
      final size = transferResultSize(task);
      return size.isEmpty ? statusText(status) : '已完成 · $size';
    case 'completedWithSkips':
      final size = transferResultSize(task);
      return size.isEmpty ? '已完成 · 部分内容已跳过' : '已完成 · 部分内容已跳过 · $size';
    case 'partial':
      return progress.isEmpty ? '部分完成，请核对逐项结果' : '部分完成 · $progress';
    case 'partialFailure':
      return progress.isEmpty ? '部分传输失败，请核对逐项结果' : '部分传输失败 · $progress';
    case 'queued':
    case 'running':
    case 'finalizing':
    case 'cancelling':
      return progress.isEmpty
          ? statusText(status)
          : '${statusText(status)} · $progress';
    default:
      return progress.isEmpty
          ? statusText(status)
          : '${statusText(status)} · $progress';
  }
}
