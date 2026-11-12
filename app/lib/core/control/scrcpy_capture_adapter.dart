import 'package:media_codec/media_codec.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 将产品命令转换为通用协议能力；只附着会话所有者已创建的捕获。
final class ScrcpyCaptureAdapter {
  ScrcpyCaptureAdapter(this.api) : _scrcpy = ScrcpyClient(api);

  final NativeScrcpyApi api;
  final ScrcpyClient _scrcpy;

  Future<MediaCodecSource> openSource({
    required String captureRef,
    required String sourceId,
    required int generation,
  }) async {
    if (captureRef.isEmpty) {
      throw const RequestFailure('invalid_endpoint', '缺少精确的视频捕获身份。');
    }
    final ScrcpySession session;
    try {
      session = await _scrcpy.attach(captureRef, generation: generation);
    } on ScrcpyException catch (error) {
      throw RequestFailure(error.code, error.message);
    }
    try {
      final source = session.info?.source;
      if (source == null || source.sourceId != sourceId) {
        throw const RequestFailure('stale_capture', '视频输入已被替换。');
      }
      return MediaCodecSource(
        sourceId: source.sourceId,
        generation: source.generation,
        codec: source.codec,
        width: source.width,
        height: source.height,
        attachAddress: source.attachAddress,
        detachAddress: source.detachAddress,
      );
    } on ScrcpyException catch (error) {
      throw RequestFailure(error.code, error.message);
    } finally {
      // 此附着不持有停止权；释放观察对象不会取消原生捕获。
      await session.close();
    }
  }
}
