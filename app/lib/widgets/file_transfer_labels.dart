import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';

FileTransferSnapshot transferView(
  Iterable<DeviceSnapshot> devices,
  FileTransferSnapshot task,
) {
  final matches = devices.where((device) => device.id == task.deviceId);
  final name = matches.isEmpty
      ? task.deviceName ?? '被控设备'
      : deviceName(matches.first);
  final pulling = task.direction == FileTransferDirection.pull;
  final status = task.kind == .directory && task.status == .completed
      ? !task.treeVerified
            ? FileTransferStatus.finalizing
            : !task.canExport
            ? FileTransferStatus.partial
            : task.status
      : task.status;
  return task.copyWith(
    status: status,
    totalBytes: task.totalBytes ?? task.total,
    completedBytes: task.completedBytes ?? task.transferred,
    sourceLabel: task.sourceLabel ?? (pulling ? name : '本机'),
    destinationLabel:
        task.destinationLabel ??
        (pulling
            ? task.destinationScope == .privateCache
                  ? '本机暂存'
                  : task.destination
            : name),
    localPath: pulling && task.status == .completed && task.canExport
        ? task.localPath ?? task.destination
        : null,
  );
}

bool transferStatusHasIssue(FileTransferStatus status) => switch (status) {
  .failed || .partialFailure || .partial || .interrupted || .paused => true,
  .unknown ||
  .queued ||
  .running ||
  .finalizing ||
  .cancelling ||
  .conflict ||
  .completed ||
  .skipped ||
  .cancelled ||
  .completedWithSkips => false,
};

/// 列表只显示远端设备，暂存位置的细节在详情页说明。
String transferListDirection(FileTransferSnapshot task, String deviceName) =>
    task.direction == .push ? '发送 · 本机 → $deviceName' : '接收 · $deviceName → 本机';

/// 详情保留两端位置，并区分仍需保存到系统位置的私有暂存。
String transferDetailDirection(FileTransferSnapshot task, String deviceName) {
  if (task.direction == .push) {
    return '发送 · 本机 → $deviceName';
  }
  if (task.destinationScope == .privateCache) {
    return '接收 · $deviceName → 本机暂存';
  }
  return '接收 · $deviceName → 本机';
}

String transferByteSummary(FileTransferSnapshot task) {
  final completed = (task.completedBytes ?? task.transferred);
  final total = (task.totalBytes ?? task.total);
  if ((total == null || total <= 0) && completed <= 0) return '';
  if (total == null || total <= 0) return bytes(completed);
  final percent = ((completed / total) * 100).clamp(0, 100).floor();
  return '${bytes(completed)} / ${bytes(total)} · $percent%';
}

String transferResultSize(FileTransferSnapshot task) {
  final completed = (task.completedBytes ?? task.transferred);
  final total = (task.totalBytes ?? task.total) ?? 0;
  final actual = completed > 0 ? completed : total;
  return actual > 0 ? bytes(actual) : '';
}

/// 状态行统一呈现进度与结果；结束后显示实际字节，执行中补充进度条对应的百分比。
String transferStatusDescription(FileTransferSnapshot task) {
  if (task.errorCode == 'result_unknown' || task.cleanupPending) {
    final reason = task.error;
    return reason == null || reason.isEmpty ? '结果待核对' : '结果待核对 · $reason';
  }
  final status = task.status;
  final progress = transferByteSummary(task);
  switch (status) {
    case .failed:
      final reason = (task.error ?? '');
      return reason.isEmpty ? statusText(status.name) : '失败 · $reason';
    case .interrupted:
      final reason = (task.error ?? '连接中断，已完成部分保留');
      return '已中断 · $reason';
    case .cancelled:
      return '已停止，已完成部分保留';
    case .completed:
      final size = transferResultSize(task);
      return size.isEmpty ? statusText(status.name) : '已完成 · $size';
    case .completedWithSkips:
      final size = transferResultSize(task);
      return size.isEmpty ? '已完成 · 部分内容已跳过' : '已完成 · 部分内容已跳过 · $size';
    case .partial:
      return progress.isEmpty ? '部分完成，请核对逐项结果' : '部分完成 · $progress';
    case .partialFailure:
      return progress.isEmpty ? '部分传输失败，请核对逐项结果' : '部分传输失败 · $progress';
    case .queued:
    case .running:
    case .finalizing:
    case .cancelling:
      return progress.isEmpty
          ? statusText(status.name)
          : '${statusText(status.name)} · $progress';
    default:
      return progress.isEmpty
          ? statusText(status.name)
          : '${statusText(status.name)} · $progress';
  }
}
