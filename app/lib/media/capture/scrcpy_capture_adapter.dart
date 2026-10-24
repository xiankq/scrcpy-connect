import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

typedef CaptureJson = Map<String, dynamic>;

/// 将产品命令转换为通用协议能力；只附着会话所有者已创建的捕获。
final class ScrcpyCaptureAdapter {
  ScrcpyCaptureAdapter(this.api) : _scrcpy = ScrcpyClient(api);

  final NativeScrcpyApi api;
  final ScrcpyClient _scrcpy;

  Future<CaptureJson> openSource(CaptureJson stream, int generation) async {
    final ref = stream['captureRef'];
    if (ref is! String || ref.isEmpty) {
      throw const ApplicationCommandException(
        'invalid_endpoint',
        '缺少精确的视频捕获身份。',
      );
    }
    final ScrcpySession session;
    try {
      session = await _scrcpy.attach(ref, generation: generation);
    } on ScrcpyException catch (error) {
      throw ApplicationCommandException(error.code, error.message);
    }
    try {
      final source = session.info?.source;
      if (source == null || source.sourceId != stream['videoSourceId']) {
        throw const ApplicationCommandException('stale_capture', '视频输入已被替换。');
      }
      return {
        'sourceId': source.sourceId,
        'relayId': source.sourceId,
        'generation': source.generation,
        'container': 'packet',
        'kind': 'video',
        'codec': source.codec,
        'width': source.width,
        'height': source.height,
        'attachAddress': source.attachAddress,
        'detachAddress': source.detachAddress,
      };
    } on ScrcpyException catch (error) {
      throw ApplicationCommandException(error.code, error.message);
    } finally {
      // 此附着不持有停止权；释放观察对象不会取消原生捕获。
      await session.close();
    }
  }
}
