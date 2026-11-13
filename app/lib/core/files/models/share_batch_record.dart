import 'package:scrcpy_connect/core/files/models/shared_source_file.dart';

enum ShareBatchStatus { importing, ready, error }

/// 分享暂存账本的已校验快照，不持有文件或复制资源。
final class ShareBatchRecord {
  ShareBatchRecord({
    required this.id,
    required this.created,
    required this.status,
    this.visible = true,
    this.bytes = 0,
    this.text,
    this.mime,
    List<SharedSourceFile> files = const [],
    List<String> errors = const [],
  }) : files = List.unmodifiable(files),
       errors = List.unmodifiable(errors);

  factory ShareBatchRecord.fromJson(Map<String, dynamic> value) =>
      ShareBatchRecord(
        id: value['id'] as String,
        created: value['created'] as int,
        status: ShareBatchStatus.values.byName(value['status'] as String),
        visible: value['visible'] as bool,
        bytes: value['bytes'] as int,
        text: value['text'] as String?,
        mime: value['mime'] as String?,
        files: [
          for (final file in value['files'] as List)
            SharedSourceFile(
              diskName: file['diskName'] as String,
              name: file['name'] as String,
              size: file['size'] as int,
              directory: file['directory'] == true,
            ),
        ],
        errors: List<String>.from(value['errors'] as List),
      );

  final String id;
  final int created, bytes;
  final ShareBatchStatus status;
  final bool visible;
  final String? text, mime;
  final List<SharedSourceFile> files;
  final List<String> errors;

  ShareBatchRecord copyWith({
    ShareBatchStatus? status,
    bool? visible,
    int? bytes,
    List<SharedSourceFile>? files,
    List<String>? errors,
  }) => ShareBatchRecord(
    id: id,
    created: created,
    status: status ?? this.status,
    visible: visible ?? this.visible,
    bytes: bytes ?? this.bytes,
    text: text,
    mime: mime,
    files: files ?? this.files,
    errors: errors ?? this.errors,
  );

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'created': created,
    'status': status.name,
    'visible': visible,
    'bytes': bytes,
    'text': text,
    'mime': mime,
    'files': files.map((file) => file.toJson()).toList(),
    'errors': errors,
  };
}
