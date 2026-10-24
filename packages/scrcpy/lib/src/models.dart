/// 当前上游捕获支持的视频编码。
enum ScrcpyVideoCodec { h264, h265, av1, vp8, vp9 }

/// 固定服务端支持的日志等级，由调用方明确选择。
enum ScrcpyLogLevel { verbose, debug, info, warn, error }

enum ScrcpySourceState { waiting, streaming, closed }

enum ScrcpySourceKind { video, audio }

/// 精确来源的原生接纳事实，不代表解码、呈现或音频播放已完成。
final class ScrcpySourceStatus {
  const ScrcpySourceStatus({
    required this.captureRef,
    required this.sourceId,
    required this.generation,
    required this.kind,
    required this.codec,
    required this.status,
    required this.packets,
    required this.bytes,
  });

  final String captureRef;
  final String sourceId;

  /// 当前原生 sink 的实际代次；尚未 attach 时为 0。
  final int generation;
  final ScrcpySourceKind kind;
  final String codec;
  final ScrcpySourceState status;

  /// 原生 sink 已接纳的数据包数；重试和未接纳的数据包不计入。
  final int packets;

  /// 上述已接纳数据包的字节数。
  final int bytes;
}

/// 上游 `new_display` 参数；空宽高由被控端选择。
final class ScrcpyDisplayOptions {
  const ScrcpyDisplayOptions({this.width, this.height, this.density});
  final int? width;
  final int? height;
  final int? density;
}

/// 已解析的上游捕获参数；不含产品画质档位或逻辑窗口身份。
final class ScrcpyOptions {
  const ScrcpyOptions({
    this.logLevel = ScrcpyLogLevel.debug,
    this.video = true,
    this.audio = false,
    this.displayId = 0,
    this.keepActive = false,
    this.powerOffOnClose = false,
    this.stayAwake = false,
    this.cleanup = true,
    this.videoCodec = ScrcpyVideoCodec.h264,
    this.videoBitRate = 8000000,
    this.maxSize = 0,
    this.maxFps = 0,
    this.videoEncoder,
    this.display,
    this.control = true,
    this.powerOn = true,
    this.clipboardAutosync = true,
    this.vdDestroyContent = true,
    this.flexDisplay = false,
    this.vdSystemDecorations = true,
    this.repeatPreviousFrameAfterUs,
  });

  /// 默认与固定服务端 Options 一致，不因虚拟显示存在而改变。
  final ScrcpyLogLevel logLevel;
  final bool video;

  /// 当前原生音频支持 raw/output 双声道 PCM，不覆盖麦克风及有损音频编码。
  final bool audio;
  final int displayId;
  final bool keepActive;
  final bool powerOffOnClose;
  final bool stayAwake;
  final bool cleanup;
  final ScrcpyVideoCodec videoCodec;
  final int videoBitRate;

  /// 0 表示不限制编码长边。
  final int maxSize;

  /// 支持上游帧率的非负整数子集；0 表示不限，当前入口不接收小数帧率。
  final int maxFps;
  final String? videoEncoder;
  final ScrcpyDisplayOptions? display;
  final bool control;
  final bool powerOn;
  final bool clipboardAutosync;
  final bool vdDestroyContent;
  final bool flexDisplay;
  final bool vdSystemDecorations;

  /// 可选编码器 `repeat-previous-frame-after` 参数；null 表示不覆盖编码器默认值。
  final int? repeatPreviousFrameAfterUs;
}

/// 原生包通道描述。地址仅在当前宿主进程有效，禁止持久化；媒体字节不经过 Dart。
final class ScrcpyNativeSource {
  const ScrcpyNativeSource({
    required this.sourceId,
    required this.generation,
    required this.codec,
    required this.width,
    required this.height,
    required this.attachAddress,
    required this.detachAddress,
  });
  final String sourceId;

  final int generation;
  final String codec;
  final int width;
  final int height;
  final int attachAddress;
  final int detachAddress;
}

final class ScrcpySessionInfo {
  const ScrcpySessionInfo({
    required this.id,
    required this.deviceName,
    required this.videoCodec,
    required this.width,
    required this.height,
    this.source,
    this.audioSource,
    this.videoEnabled = true,
    this.audioEnabled = false,
    this.controlReady = true,
    this.mediaReady = true,
    this.processId,
    this.processStarted,
  });

  /// 精确捕获句柄，独立于调用方的逻辑窗口。
  final String id;
  final String deviceName;
  final ScrcpyVideoCodec videoCodec;
  final int width;
  final int height;
  final ScrcpyNativeSource? source;
  final ScrcpyNativeSource? audioSource;
  final bool videoEnabled;
  final bool audioEnabled;

  /// 控制通道已接纳；不表示应用已经启动或输入已被系统处理。
  final bool controlReady;

  /// 视频首关键帧已读取，或纯音频格式已验证；不表示播放器已经呈现。
  final bool mediaReady;
  final int? processId;

  /// 被控进程的内核启动标识，禁止当作本机时间戳解释。
  final int? processStarted;
}

final class ScrcpyProcessInfo {
  const ScrcpyProcessInfo({
    required this.pid,
    required this.started,
    required this.logTail,
    required this.truncated,
  });
  final int pid;
  final int started;
  final List<int> logTail;
  final bool truncated;
}

/// 元数据事件；流不缓冲重播媒体内容。
sealed class ScrcpyEvent {
  const ScrcpyEvent();
}

final class ScrcpyClipboardChanged extends ScrcpyEvent {
  const ScrcpyClipboardChanged(this.text);
  final String text;
}

final class ScrcpyStopped extends ScrcpyEvent {
  const ScrcpyStopped({this.reason});
  final String? reason;
}

final class ScrcpyException implements Exception {
  const ScrcpyException(this.code, [this.message = '']);
  final String code;
  final String message;
  @override
  String toString() =>
      'ScrcpyException($code${message.isEmpty ? '' : ': $message'})';
}
