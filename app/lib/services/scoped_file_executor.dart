/// 已完成执行域接管的事实；同 key 换发 id 前必须实际排空旧域的操作与片段。
///
/// 这两个值来自执行能力的真实 attach，不是产品设备 ID，也不授予旧域关闭权。
abstract interface class ScopedFileExecutor {
  String get fileScopeKey;
  String get fileScopeId;
}
