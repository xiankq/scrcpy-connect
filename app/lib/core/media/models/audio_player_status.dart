/// 原生输出证据独立于源 PCM 包与播放时钟，不表示已经核验扬声器样本。
final class AudioPlayerStatus {
  const AudioPlayerStatus({
    required this.nativeReady,
    required this.bytesWritten,
  });
  factory AudioPlayerStatus.fromProtocol(Map<String, dynamic> value) =>
      AudioPlayerStatus(
        nativeReady: value['nativeReady'] == true,
        bytesWritten: value['bytesWritten'] as int? ?? 0,
      );
  final bool nativeReady;
  final int bytesWritten;
}
