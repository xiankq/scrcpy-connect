enum DocumentSelectionMode {
  importDirectory,
  importFiles,
  exportDirectory,
  exportFile,
  desktopExport,
}

final class DocumentSelectionRequest {
  const DocumentSelectionRequest({
    required this.operationId,
    required this.mode,
    this.ownerLeaseId,
    this.name,
    this.mime,
  });
  final String operationId;
  final DocumentSelectionMode mode;
  final String? ownerLeaseId, name, mime;

  /// 仅在系统选择器的 MethodChannel 边界编码。
  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'mode': mode.name,
    'ownerLeaseId': ?ownerLeaseId,
    'name': ?name,
    'mime': ?mime,
  };
}

/// 平台持有访问授权，应用携带本次操作内的不透明引用。
final class SelectedDocument {
  const SelectedDocument({required this.handle, required this.uri});
  final String handle, uri;

  factory SelectedDocument.fromJson(Map<String, Object?> json) =>
      SelectedDocument(
        handle: json['handle']! as String,
        uri: json['uri']! as String,
      );

  Map<String, Object?> toJson() => {'handle': handle, 'uri': uri};
}

sealed class DocumentSelectionResult {
  const DocumentSelectionResult();

  /// 只解析实际平台回执；内部请求、取消与失败直接使用对应类型。
  factory DocumentSelectionResult.fromJson(Map<String, Object?> json) =>
      switch (json['status']) {
        'cancelled' => const DocumentSelectionCancelled(),
        'failed' => DocumentSelectionFailed(
          json['code'] as String? ?? 'selection_failed',
          json['message'] as String? ?? '无法读取所选位置。',
        ),
        'selected' => DocumentLocationsSelected([
          for (final entry in json['documents']! as List<Object?>)
            SelectedDocument.fromJson(Map<String, Object?>.from(entry! as Map)),
        ]),
        _ => throw const FormatException('系统没有返回有效的文档选择结果。'),
      };
}

final class DocumentLocationsSelected extends DocumentSelectionResult {
  DocumentLocationsSelected(List<SelectedDocument> documents)
    : documents = List.unmodifiable(documents);
  final List<SelectedDocument> documents;
}

final class DocumentDestinationSelected extends DocumentSelectionResult {
  const DocumentDestinationSelected(this.path);
  final String path;
}

final class DocumentSelectionCancelled extends DocumentSelectionResult {
  const DocumentSelectionCancelled();
}

final class DocumentSelectionFailed extends DocumentSelectionResult {
  const DocumentSelectionFailed(this.code, this.message);
  final String code, message;
}
