import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 同一媒体描述符的身份及时间事实；缺失的纳秒精度保持未知。
final class ThumbnailSource {
  factory ThumbnailSource({
    required String device,
    required String inode,
    required int mode,
    required int size,
    required int modifiedSeconds,
    required int changedSeconds,
    int? modifiedNanos,
    int? changedNanos,
  }) {
    if (mode & 0xf000 != 0x8000 ||
        size < 0 ||
        size > 64 * 1024 * 1024 * 1024 ||
        int.tryParse(device) == null ||
        int.tryParse(inode) == null) {
      throw const RequestFailure('invalid_data', '缩略图源元数据无效。');
    }
    for (final nanos in [modifiedNanos, changedNanos]) {
      if (nanos != null && (nanos < 0 || nanos >= 1000000000)) {
        throw const RequestFailure('invalid_data', '缩略图源时间精度无效。');
      }
    }
    return ThumbnailSource._(
      device: device,
      inode: inode,
      mode: mode,
      size: size,
      modifiedSeconds: modifiedSeconds,
      changedSeconds: changedSeconds,
      modifiedNanos: modifiedNanos,
      changedNanos: changedNanos,
    );
  }

  const ThumbnailSource._({
    required this.device,
    required this.inode,
    required this.mode,
    required this.size,
    required this.modifiedSeconds,
    required this.changedSeconds,
    required this.modifiedNanos,
    required this.changedNanos,
  });

  factory ThumbnailSource.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const RequestFailure('invalid_data', '缩略图源元数据无效。');
    }
    final mode = value['mode'], size = value['size'];
    final device = value['device'], inode = value['inode'];
    final modified = value['modifiedSeconds'],
        changed = value['changedSeconds'];
    if (mode is! int ||
        size is! int ||
        device is! String ||
        inode is! String ||
        modified is! int ||
        changed is! int) {
      throw const RequestFailure('invalid_data', '缩略图源元数据无效。');
    }
    final modifiedNanos = value['modifiedNanos'],
        changedNanos = value['changedNanos'];
    for (final nanos in [modifiedNanos, changedNanos]) {
      if (nanos != null && nanos is! int) {
        throw const RequestFailure('invalid_data', '缩略图源时间精度无效。');
      }
    }
    return ThumbnailSource(
      device: device,
      inode: inode,
      mode: mode,
      size: size,
      modifiedSeconds: modified,
      changedSeconds: changed,
      modifiedNanos: modifiedNanos as int?,
      changedNanos: changedNanos as int?,
    );
  }

  final String device, inode;
  final int mode, size, modifiedSeconds, changedSeconds;
  final int? modifiedNanos, changedNanos;

  Map<String, Object?> toJson() => {
    'device': device,
    'inode': inode,
    'mode': mode,
    'size': size,
    'modifiedSeconds': modifiedSeconds,
    'changedSeconds': changedSeconds,
    'modifiedNanos': modifiedNanos,
    'changedNanos': changedNanos,
  };

  @override
  bool operator ==(Object other) =>
      other is ThumbnailSource &&
      device == other.device &&
      inode == other.inode &&
      mode == other.mode &&
      size == other.size &&
      modifiedSeconds == other.modifiedSeconds &&
      changedSeconds == other.changedSeconds &&
      modifiedNanos == other.modifiedNanos &&
      changedNanos == other.changedNanos;

  @override
  int get hashCode => Object.hash(
    device,
    inode,
    mode,
    size,
    modifiedSeconds,
    changedSeconds,
    modifiedNanos,
    changedNanos,
  );
}
