import 'package:freezed_annotation/freezed_annotation.dart';

part 'incoming_shares.freezed.dart';
part 'incoming_shares.g.dart';

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

abstract interface class IncomingShares {
  Future<List<IncomingShare>> readIncomingShares();

  /// 排空此分享的复制工作后归还页面持有权；在途发布租约继续保护来源。
  Future<void> consumeShare(String id);
}
