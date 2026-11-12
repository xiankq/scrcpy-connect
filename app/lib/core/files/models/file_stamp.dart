class FileStamp {
  const FileStamp({
    required this.mode,
    required this.size,
    required this.modifiedSeconds,
    this.modifiedNanos = 0,
    this.modifiedResolutionNanos = 1,
    this.identity,
  });
  final int mode, size, modifiedSeconds, modifiedNanos;
  final String? identity;

  /// 可观察时间分辨率：1 为纳秒、1000 为微秒、1e9 为秒；旧日志按纳秒保守核对。
  final int modifiedResolutionNanos;
  bool get isFile => mode & 0xf000 == 0x8000;
  bool get isDirectory => mode & 0xf000 == 0x4000;
  bool get isLink => mode & 0xf000 == 0xa000;
  String get kind => switch (mode & 0xf000) {
    0x8000 => 'file',
    0x4000 => 'directory',
    0xa000 => 'symlink',
    _ => 'unsupported',
  };
  Map<String, Object?> toJson() => {
    'identity': ?identity,
    'mode': mode,
    'size': size,
    'modifiedSeconds': modifiedSeconds,
    'modifiedNanos': modifiedNanos,
    'modifiedResolutionNanos': modifiedResolutionNanos,
  };
  factory FileStamp.fromJson(Map<String, Object?> value) => FileStamp(
    identity: value['identity'] as String?,
    mode: value['mode']! as int,
    size: value['size']! as int,
    modifiedSeconds: value['modifiedSeconds']! as int,
    modifiedNanos: value['modifiedNanos'] as int? ?? 0,
    modifiedResolutionNanos: _resolution(value['modifiedResolutionNanos']),
  );
  static int _resolution(Object? value) {
    if (value == null) return 1;
    if (value is int && (value == 1 || value == 1000 || value == 1000000000)) {
      return value;
    }
    throw const FormatException('文件时间戳分辨率无效。');
  }

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      identity == other.identity &&
      mode == other.mode &&
      size == other.size &&
      modifiedSeconds == other.modifiedSeconds &&
      modifiedNanos == other.modifiedNanos &&
      modifiedResolutionNanos == other.modifiedResolutionNanos;
  @override
  int get hashCode => Object.hash(
    identity,
    mode,
    size,
    modifiedSeconds,
    modifiedNanos,
    modifiedResolutionNanos,
  );
}
