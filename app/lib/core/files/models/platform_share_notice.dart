import 'package:scrcpy_connect/core/files/file_failure.dart';

/// 平台分享入口交付的不可变通知；来源仍由对应平台租约持有。
final class PlatformShareNotice {
  PlatformShareNotice({
    required this.shareId,
    required this.sourceCount,
    this.text,
    this.mime,
    this.rejected = false,
    List<String> errors = const [],
  }) : errors = List.unmodifiable(errors);

  factory PlatformShareNotice.fromJson(Object? value) {
    if (value is! Map) _invalid();
    final id = value['shareId'];
    final text = value['text'];
    final mime = value['mime'];
    final status = value['status'];
    final errors = value['errors'] ?? const <String>[];
    final rejected = status == 'error';
    final count = value['sourceCount'] ?? (rejected ? 0 : null);
    if (id is! String ||
        id.isEmpty ||
        text != null && text is! String ||
        mime != null && mime is! String ||
        status != null && status != 'error' ||
        count is! int ||
        errors is! List ||
        errors.any((error) => error is! String)) {
      _invalid();
    }
    return PlatformShareNotice(
      shareId: id,
      sourceCount: count,
      text: text as String?,
      mime: mime as String?,
      rejected: rejected,
      errors: List<String>.from(errors),
    );
  }

  final String shareId;
  final int sourceCount;
  final String? text, mime;
  final bool rejected;
  final List<String> errors;
}

Never _invalid() => throw const FileFailure('invalid_share', '平台分享通知格式无效。');
