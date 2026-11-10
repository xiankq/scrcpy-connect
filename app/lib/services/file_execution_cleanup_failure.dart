import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/services/file_execution_resource.dart';

/// 单次便捷调用回收失败时，把精确执行对象交还调用者，而非只保留错误文本。
final class FileExecutionCleanupFailure extends FileFailure {
  FileExecutionCleanupFailure(this.execution, this.cause)
    : super('file_cleanup_unconfirmed', '文件执行资源尚未确认释放：$cause');
  final FileExecutionResource execution;
  final Object cause;
}
