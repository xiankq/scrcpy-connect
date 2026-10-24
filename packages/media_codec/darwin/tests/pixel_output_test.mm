// 在 macOS 上使用插件实现、FlutterMacOS 框架、锁定版本的 FFmpeg/核心及
// CoreImage/Metal 框架编译；该夹具校验实际转换像素。
#include "../Classes/MediaCodecPlugin.mm"
#include <cstdlib>
#include <iostream>
#include <thread>
#include <chrono>

static void Check(bool value, const char* message) {
  if (!value) { std::cerr << message << "\n"; std::abort(); }
}
static void Red(CVPixelBufferRef buffer) {
  Check(buffer != NULL, "no output buffer");
  Check(CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess, "lock failed");
  auto* pixel = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(buffer));
  Check(pixel[0] < 12 && pixel[1] < 12 && pixel[2] > 240 && pixel[3] == 255, "red color/range conversion is wrong");
  CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
}
static AVFrame* Software(AVColorSpace space, AVColorRange range, uint8_t y, uint8_t u, uint8_t v) {
  AVFrame* frame = av_frame_alloc(); frame->width = 16; frame->height = 16;
  frame->format = AV_PIX_FMT_YUV420P; frame->colorspace = space; frame->color_range = range;
  Check(av_frame_get_buffer(frame, 32) == 0, "frame allocation failed");
  for (int row = 0; row < 16; ++row) memset(frame->data[0] + row * frame->linesize[0], y, 16);
  for (int row = 0; row < 8; ++row) {
    memset(frame->data[1] + row * frame->linesize[1], u, 8);
    memset(frame->data[2] + row * frame->linesize[2], v, 8);
  }
  return frame;
}
int main() {
  @autoreleasepool {
    MCMediaOutput* output = [[MCMediaOutput alloc] init];
    for (auto values : {std::vector<int>{AVCOL_SPC_SMPTE170M, AVCOL_RANGE_MPEG, 81, 90, 240},
                        std::vector<int>{AVCOL_SPC_BT709, AVCOL_RANGE_MPEG, 63, 102, 240},
                        std::vector<int>{AVCOL_SPC_SMPTE170M, AVCOL_RANGE_JPEG, 76, 85, 255}}) {
      AVFrame* frame = Software((AVColorSpace)values[0], (AVColorRange)values[1], values[2], values[3], values[4]);
      for (int iteration = 0; iteration < 12; ++iteration) {
        CVPixelBufferRef buffer = [output convertFrame:frame]; Red(buffer); CVPixelBufferRelease(buffer);
      }
      av_frame_free(&frame);
    }
    // NV12 709 路径必须通过 Metal 转换，因为 Flutter 将原生 NV12 解释为 601。
    // 该夹具按 601 转换时会出现明显的非零绿色分量。
    CVPixelBufferRef nv12 = NULL;
    NSDictionary* attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
    Check(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        (__bridge CFDictionaryRef)attrs, &nv12) == kCVReturnSuccess, "NV12 allocation failed");
    CVPixelBufferLockBaseAddress(nv12, 0);
    for (size_t row = 0; row < 16; ++row)
      memset((uint8_t*)CVPixelBufferGetBaseAddressOfPlane(nv12, 0) + row * CVPixelBufferGetBytesPerRowOfPlane(nv12, 0), 63, 16);
    for (size_t row = 0; row < 8; ++row) {
      uint8_t* uv = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(nv12, 1) + row * CVPixelBufferGetBytesPerRowOfPlane(nv12, 1);
      for (int x = 0; x < 16; x += 2) { uv[x] = 102; uv[x + 1] = 240; }
    }
    CVPixelBufferUnlockBaseAddress(nv12, 0);
    AVFrame* frame = av_frame_alloc(); frame->width = 16; frame->height = 16;
    frame->format = AV_PIX_FMT_VIDEOTOOLBOX; frame->colorspace = AVCOL_SPC_BT709;
    frame->color_primaries = AVCOL_PRI_BT709; frame->color_trc = AVCOL_TRC_BT709;
    frame->data[3] = (uint8_t*)nv12;
    CVPixelBufferRef converted = [output convertFrame:frame]; Red(converted);
    Check(converted != nv12, "709 NV12 bypassed matrix correction");
    CVPixelBufferRelease(converted); frame->data[3] = NULL; av_frame_free(&frame); CVPixelBufferRelease(nv12);
    [output close];
    // 在没有传输源的情况下验证系统 AudioQueue。
    // 附着失败后，平台音频仍由当前实例拥有，直到显式或终止清理。
    MCMediaOutput* audio = [[MCMediaOutput alloc] init];
    Check(![audio open:@{@"sourceId": @"fixture", @"attachAddress": @0,
                        @"detachAddress": @0} audio:YES], "invalid attach unexpectedly succeeded");
    Check(audio->_audioQueue != NULL, "AudioQueue could not be created");
    uint8_t silence[3840] = {};
    Check([audio writePCM:silence length:sizeof(silence)] == sizeof(silence), "AudioQueue rejected PCM");
    mc_audio_state before = {}, paused = {};
    Check([audio audioState:&before] == 0 && before.running, "AudioQueue clock did not start");
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    uint8_t resumedSilence[11520] = {};
    Check([audio writePCM:resumedSilence length:sizeof(resumedSilence)] == sizeof(resumedSilence), "underrun recovery rejected PCM");
    Check([audio audioState:&before] == 0 && before.queued_frames > 0,
          "underrun recovery counted late PCM as already played");
    [audio pauseAudio:YES];
    Check([audio audioState:&paused] == 0 && !paused.running && paused.queued_frames == 0 &&
          paused.generation > before.generation, "pause did not flush/reset AudioQueue clock");
    [audio pauseAudio:NO];
    Check([audio writePCM:resumedSilence length:sizeof(resumedSilence)] == sizeof(resumedSilence), "resume rejected PCM");
    Check([audio audioState:&paused] == 0 && paused.running && paused.queued_frames > 0,
          "resumed AudioQueue used the previous generation's clock");
    [audio closeAudio];
    Check([audio audioState:&paused] < 0 && audio->_audioQueue == NULL, "terminal close kept audio alive");
    [audio close]; [audio close];
    std::cout << "Apple 601/709/full-range software pixels, pooled reuse, Metal NV12 709, AudioQueue pause/flush/close passed\n";
  }
}
