import 'package:freezed_annotation/freezed_annotation.dart';

part 'video_renderer_receipt.freezed.dart';

/// 精确捕获、渲染代次和纹理的回执；尺寸与帧计数只能更新同一绑定。
@freezed
abstract class VideoRendererReceipt with _$VideoRendererReceipt {
  const factory VideoRendererReceipt({
    required String sessionId,
    String? deviceId,
    String? expectedCaptureRef,
    required int captureGeneration,
    required int generation,
    required int textureId,
    int? decodedWidth,
    int? decodedHeight,
    int? frameCount,
    int? framesDecoded,
    int? presentationTimeUs,
    String? decoder,
    String? renderer,
    String? hardwareAcceleration,
    bool? hardwareAccelerated,
  }) = _VideoRendererReceipt;
}
