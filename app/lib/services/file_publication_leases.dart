import 'dart:async';

/// 记录分享来源与传输批次的发布关系，保护仍被任务引用的导入缓存。
/// 导入描述符只在读取来源期间存活，不由发布记录持有。
abstract interface class FilePublicationLeases {
  /// 当前受管来源的快照；后续核对只可对明确覆盖的来源作出完整性结论。
  Future<Set<String>> get sourcePaths;

  /// 在发布任何任务前绑定本次批次；缺少身份的旧未知记录不能按路径认领。
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request, {
    String? transferId,
  });
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  });
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  });
}

/// 受管来源可在调用方未传发布标识时识别归属，禁止绕过持久租约。
abstract interface class ManagedFilePublicationLeases
    implements FilePublicationLeases {
  Future<String?> ownerForSources(List<String> sources);
}
