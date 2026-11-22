import 'package:scrcpy_connect/core/errors/failure_message.dart';
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
    task.direction == .push ? '本机 → $deviceName' : '$deviceName → 本机';

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

/// Details can provide guidance without repeating native or persisted text.
String transferIssueMessage(FileTransferSnapshot task) {
  if (task.cleanupPending || task.errorCode == 'result_unknown') {
    return '暂时无法确认哪些文件已传完。请先查看目标位置，再决定是否重试。';
  }
  return failureCodeMessage(
    task.errorCode,
    fallback: switch (task.status) {
      .paused => '传输已暂停。检查手机连接后，可以继续传输。',
      .interrupted => '传输已中断，已完成的部分会保留。请查看详情后再继续。',
      .partial || .partialFailure => '只传完了部分文件。请在详情中查看哪些文件未完成。',
      _ => '传输未能完成。请检查手机连接和目标位置后再试。',
    },
  );
}

/// 状态行统一呈现进度与结果；结束后显示实际字节，执行中补充进度条对应的百分比。
String transferStatusDescription(FileTransferSnapshot task) {
  if (task.errorCode == 'result_unknown' || task.cleanupPending) {
    return '结果待确认';
  }
  final status = task.status;
  final progress = transferByteSummary(task);
  switch (status) {
    case .failed:
      return '传输失败';
    case .interrupted:
      return '已中断，已完成部分保留';
    case .cancelled:
      return '已停止，已完成部分保留';
    case .completed:
      final size = transferResultSize(task);
      return size.isEmpty ? statusText(status.name) : '已完成 · $size';
    case .completedWithSkips:
      final size = transferResultSize(task);
      return size.isEmpty ? '已完成 · 部分内容已跳过' : '已完成 · 部分内容已跳过 · $size';
    case .partial:
      return progress.isEmpty ? '部分完成，请查看每项结果' : '部分完成 · $progress';
    case .partialFailure:
      return progress.isEmpty ? '部分传输失败，请查看每项结果' : '部分传输失败 · $progress';
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
