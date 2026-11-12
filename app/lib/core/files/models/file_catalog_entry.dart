import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';

part 'file_catalog_entry.freezed.dart';
part 'file_catalog_entry.g.dart';

enum FileCatalogFilter {
  all,
  folders,
  images,
  videos,
  audio,
  documents,
  archives,
}

/// 目录事实的应用投影；名称可呈现不代表路径有效或允许操作。
@freezed
abstract class FileCatalogEntry with _$FileCatalogEntry {
  const factory FileCatalogEntry({
    @Default('') String name,
    String? path,
    @Default('file') String kind,
    @Default(false) bool isDirectory,
    @Default(false) bool isSymlink,
    @Default(true) bool nameIsUtf8,
    @Default(true) bool canOpen,
    @Default(true) bool canManage,
    int? size,
    int? modified,
    @Default(0) int modifiedSeconds,
    @Default('application/octet-stream') String mime,
    @Default(0) int mode,
    String? sourceIdentity,
    @JsonKey(fromJson: _readStamp, toJson: _writeStamp, includeIfNull: false)
    FileStamp? sourceStamp,
    @Default(false) bool selectable,
    @JsonKey(includeIfNull: false) String? errorCode,
    @JsonKey(includeIfNull: false) String? reason,
  }) = _FileCatalogEntry;
  factory FileCatalogEntry.fromJson(Map<String, dynamic> json) =>
      _$FileCatalogEntryFromJson(json);
}

FileStamp? _readStamp(Map<String, dynamic>? value) =>
    value == null ? null : FileStamp.fromJson(value);
Map<String, Object?>? _writeStamp(FileStamp? stamp) => stamp?.toJson();

@freezed
abstract class FileCatalogIssue with _$FileCatalogIssue {
  const factory FileCatalogIssue({
    required String path,
    required String code,
    required String reason,
  }) = _FileCatalogIssue;
  factory FileCatalogIssue.fromJson(Map<String, dynamic> json) =>
      _$FileCatalogIssueFromJson(json);
}
