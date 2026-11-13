import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 系统文档提供方的一次元数据快照；访问授权仍由平台操作持有。
final class ProviderDocument {
  const ProviderDocument({
    required this.handle,
    required this.uri,
    required this.authority,
    required this.id,
    required this.name,
    required this.directory,
    required this.virtual,
    required this.canCreate,
    required this.canWrite,
    this.size,
    this.modified,
  });

  factory ProviderDocument.fromJson(Object? value) {
    if (value is! Map) _invalid();
    String text(String key) {
      final item = value[key];
      if (item is! String) _invalid();
      return item;
    }

    bool flag(String key) {
      final item = value[key];
      if (item is! bool) _invalid();
      return item;
    }

    int? number(String key) {
      final item = value[key];
      if (item == null) return null;
      if (item is! int || item < 0) _invalid();
      return item;
    }

    return ProviderDocument(
      handle: text('handle'),
      uri: text('uri'),
      authority: text('authority'),
      id: text('id'),
      name: text('name'),
      directory: flag('directory'),
      virtual: flag('virtual'),
      canCreate: flag('canCreate'),
      canWrite: flag('canWrite'),
      size: number('size'),
      modified: number('modified'),
    );
  }

  final String handle, uri, authority, id, name;
  final bool directory, virtual, canCreate, canWrite;
  final int? size, modified;
}

final class ProviderDocumentPage {
  ProviderDocumentPage({
    required List<ProviderDocument> documents,
    required this.hasMore,
    required this.loading,
  }) : documents = List.unmodifiable(documents);

  factory ProviderDocumentPage.fromJson(Map<String, Object?> value) {
    final documents = value['documents'];
    final hasMore = value['hasMore'];
    final loading = value['loading'];
    if (documents is! List || hasMore is! bool || loading is! bool) _invalid();
    return ProviderDocumentPage(
      documents: documents.map(ProviderDocument.fromJson).toList(),
      hasMore: hasMore,
      loading: loading,
    );
  }

  final List<ProviderDocument> documents;
  final bool hasMore, loading;
}

Never _invalid() => throw const RequestFailure(
  'invalid_document_response',
  '系统文档提供方返回了无效的文档数据，未将其视为空目录。',
);
