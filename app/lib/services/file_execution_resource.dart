import 'dart:async';

/// 一次精确执行的回收责任；失败后保留同一对象重试，不关闭共享连接。
abstract interface class FileExecutionResource {
  Future<void> close();
}
