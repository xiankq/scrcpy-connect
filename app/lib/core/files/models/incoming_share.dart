import 'package:freezed_annotation/freezed_annotation.dart';

part 'incoming_share.freezed.dart';
part 'incoming_share.g.dart';

enum IncomingShareStatus { starting, importing, ready, error, submitted }

@freezed
abstract class IncomingShareFile with _$IncomingShareFile {
  const factory IncomingShareFile({
    required String name,
    required String localPath,
    required int size,
  }) = _IncomingShareFile;
  factory IncomingShareFile.fromJson(Map<String, Object?> json) =>
      _$IncomingShareFileFromJson(json);
}

@freezed
abstract class IncomingShare with _$IncomingShare {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory IncomingShare({
    required String shareId,
    required IncomingShareStatus status,
    @Default('') String text,
    String? mime,
    @Default([]) List<IncomingShareFile> files,
    @Default([]) List<String> errors,
  }) = _IncomingShare;
  factory IncomingShare.fromJson(Map<String, Object?> json) =>
      _$IncomingShareFromJson(json);
}
