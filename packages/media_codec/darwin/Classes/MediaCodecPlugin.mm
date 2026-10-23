#import "MediaCodecPlugin.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <AVFAudio/AVAudioSession.h>
#endif
#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <vector>
#include "media_codec.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
}

@interface MCMediaOutput : NSObject <FlutterTexture> {
 @public
  mc_decoder *_decoder;
  CVPixelBufferRef _pixelBuffer;
  CVPixelBufferPoolRef _pixelPool;
  AVFrame *_latestFrame;
  uint64_t _latestSequence;
  uint64_t _convertedSequence;
  CIContext *_imageContext;
  SwsContext *_scaler;
  std::mutex _audioControlMutex;
  uint64_t _audioFramesSubmitted;
  double _audioClockOrigin;
  uint64_t _audioGeneration;
  std::atomic<bool> _audioInterrupted;
  bool _ownsAudioSession;
  std::mutex _pixelMutex;
  std::mutex _audioMutex;
  std::vector<AudioQueueBufferRef> _audioBuffers;
  AudioQueueRef _audioQueue;
  std::atomic<bool> _disposed;
  std::atomic<bool> _notificationPending;
  std::atomic<bool> _audioPaused;
  bool _audioStarted;
}
@property(nonatomic) int64_t handle;
@property(nonatomic) int64_t textureId;
@property(nonatomic, strong) NSObject<FlutterTextureRegistry> *textures;
- (BOOL)open:(NSDictionary *)arguments audio:(BOOL)audio;
- (void)close;
- (void)publishFrame;
- (int64_t)writePCM:(const uint8_t *)bytes length:(size_t)length;
- (void)recycleAudioBuffer:(AudioQueueBufferRef)buffer;
- (void)setPaused:(BOOL)paused;
- (void)pauseAudio:(BOOL)paused;
- (void)closeAudio;
- (int32_t)audioState:(mc_audio_state *)state;
- (CVPixelBufferRef)convertFrame:(AVFrame *)frame;
#if TARGET_OS_IOS
- (void)audioInterruption:(NSNotification *)notification;
- (void)audioRouteChanged:(NSNotification *)notification;
#endif
@end

static void MCFrame(void *context) { [(__bridge MCMediaOutput *)context publishFrame]; }
static int64_t MCPCM(void *context, const uint8_t *bytes, size_t length) {
  return [(__bridge MCMediaOutput *)context writePCM:bytes length:length];
}
static void MCCloseAudio(void *context) { [(__bridge MCMediaOutput *)context closeAudio]; }
static void MCPause(void *context, int32_t paused) { [(__bridge MCMediaOutput *)context pauseAudio:paused != 0]; }
static int32_t MCState(void *context, mc_audio_state *state) {
  return [(__bridge MCMediaOutput *)context audioState:state];
}
#if TARGET_OS_IOS
static std::mutex MCAudioSessionMutex;
static size_t MCAudioSessionUsers = 0;
#endif
static void MCAudio(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
  [(__bridge MCMediaOutput *)context recycleAudioBuffer:buffer];
}
static uint32_t MCCodec(id value) {
  if ([value isKindOfClass:NSNumber.class]) return [value unsignedIntValue];
  if ([value isEqual:@"h264"]) return 1;
  if ([value isEqual:@"h265"] || [value isEqual:@"hevc"]) return 2;
  if ([value isEqual:@"av1"]) return 3;
  if ([value isEqual:@"vp8"]) return 4;
  if ([value isEqual:@"vp9"]) return 5;
  return 100;
}

@implementation MCMediaOutput
- (instancetype)init {
  if ((self = [super init])) {
    _textureId = -1; _disposed = false; _notificationPending = false;
    _audioPaused = false; _audioInterrupted = false;
  }
  return self;
}
- (BOOL)open:(NSDictionary *)arguments audio:(BOOL)audio {
  if (audio) {
#if TARGET_OS_IOS
    {
      std::lock_guard<std::mutex> guard(MCAudioSessionMutex);
      NSError *sessionError = nil;
      AVAudioSession *session = AVAudioSession.sharedInstance;
      if (!MCAudioSessionUsers &&
          (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                         options:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError] ||
           ![session setPreferredIOBufferDuration:0.01 error:&sessionError] ||
           ![session setActive:YES error:&sessionError])) return NO;
      ++MCAudioSessionUsers; _ownsAudioSession = true;
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioInterruption:)
        name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioRouteChanged:)
        name:AVAudioSessionRouteChangeNotification object:AVAudioSession.sharedInstance];
#endif
    AudioStreamBasicDescription format = {};
    format.mSampleRate = 48000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 4; format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4; format.mChannelsPerFrame = 2; format.mBitsPerChannel = 16;
    if (AudioQueueNewOutput(&format, MCAudio, (__bridge void *)self, NULL, NULL, 0, &_audioQueue) != noErr) return NO;
    for (int index = 0; index < 3; ++index) {
      AudioQueueBufferRef buffer = NULL;
      if (AudioQueueAllocateBuffer(_audioQueue, 3840, &buffer) != noErr) return NO;
      _audioBuffers.push_back(buffer);
    }
  }
  mc_config config = {};
  config.struct_size = sizeof(config);
  config.codec = audio ? 100 : MCCodec(arguments[@"codec"]);
  config.width = [arguments[@"width"] unsignedIntValue];
  config.height = [arguments[@"height"] unsignedIntValue];
  config.generation = [arguments[@"generation"] unsignedLongLongValue];
  config.user = (__bridge void *)self; config.frame_ready = MCFrame; config.pcm = MCPCM;
  config.audio_pause = MCPause; config.audio_state = MCState; config.audio_close = MCCloseAudio;
  _decoder = mc_create(&config);
  NSString *source = arguments[@"sourceId"];
  if (!_decoder || ![source isKindOfClass:NSString.class]) return NO;
  return mc_attach(_decoder, source.UTF8String, [arguments[@"attachAddress"] unsignedLongLongValue],
                   [arguments[@"detachAddress"] unsignedLongLongValue]) == 0;
}
// Conversion happens when Flutter consumes the latest slot, so superseded
// decoded frames never pay swscale/CoreImage work on the decoder thread.
- (CVPixelBufferRef)copyPixelBuffer {
  std::lock_guard<std::mutex> guard(_pixelMutex);
  if (_disposed) return NULL;
  if (_latestFrame && _latestSequence != _convertedSequence) {
    CVPixelBufferRef next = [self convertFrame:_latestFrame];
    if (next) {
      if (_pixelBuffer) CVPixelBufferRelease(_pixelBuffer);
      _pixelBuffer = next; _convertedSequence = _latestSequence;
      mc_report_present(_decoder, _latestSequence,
          _latestFrame->format == AV_PIX_FMT_VIDEOTOOLBOX ? "apple-videotoolbox" : "apple-software-bgra", NULL);
    } else {
      mc_report_present(_decoder, _latestSequence, "apple-texture", "Pixel buffer conversion/import failed");
    }
  }
  return _pixelBuffer ? CVPixelBufferRetain(_pixelBuffer) : NULL;
}
- (CVPixelBufferRef)convertFrame:(AVFrame *)frame {
  CVPixelBufferRef source = frame->format == AV_PIX_FMT_VIDEOTOOLBOX ? (CVPixelBufferRef)frame->data[3] : NULL;
  // Flutter's current NV12 shader always chooses BT.601. Only pass through
  // frames whose matrix agrees; other matrices are converted on the GPU.
  AVColorSpace matrix = frame->colorspace;
  if (matrix == AVCOL_SPC_UNSPECIFIED) matrix = AVCOL_SPC_BT709;
  if (source) {
    OSType format = CVPixelBufferGetPixelFormatType(source);
    if (format == kCVPixelFormatType_32BGRA ||
        ((matrix == AVCOL_SPC_SMPTE170M || matrix == AVCOL_SPC_BT470BG) &&
         (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
          format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))) return CVPixelBufferRetain(source);
  }
  if (_pixelPool) {
    CFDictionaryRef attributes = CVPixelBufferPoolGetPixelBufferAttributes(_pixelPool);
    NSDictionary *values = (__bridge NSDictionary *)attributes;
    if ([values[(id)kCVPixelBufferWidthKey] intValue] != frame->width ||
        [values[(id)kCVPixelBufferHeightKey] intValue] != frame->height) {
      CVPixelBufferPoolRelease(_pixelPool); _pixelPool = NULL;
    }
  }
  if (!_pixelPool) {
    NSDictionary *attributes = @{(id)kCVPixelBufferWidthKey: @(frame->width),
        (id)kCVPixelBufferHeightKey: @(frame->height), (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pixelPool) != kCVReturnSuccess)
      return NULL;
  }
  CVPixelBufferRef target = NULL;
  NSDictionary *limit = @{(id)kCVPixelBufferPoolAllocationThresholdKey: @4};
  if (CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _pixelPool,
      (__bridge CFDictionaryRef)limit, &target) != kCVReturnSuccess) return NULL;
  if (source) {
    CFStringRef matrixValue = matrix == AVCOL_SPC_BT2020_NCL || matrix == AVCOL_SPC_BT2020_CL
        ? kCVImageBufferYCbCrMatrix_ITU_R_2020 : matrix == AVCOL_SPC_BT709
        ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_601_4;
    CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, matrixValue, kCVAttachmentMode_ShouldPropagate);
    CFStringRef primaries = frame->color_primaries == AVCOL_PRI_BT2020 ? kCVImageBufferColorPrimaries_ITU_R_2020 :
        frame->color_primaries == AVCOL_PRI_BT709 ? kCVImageBufferColorPrimaries_ITU_R_709_2 : NULL;
    if (primaries) CVBufferSetAttachment(source, kCVImageBufferColorPrimariesKey, primaries, kCVAttachmentMode_ShouldPropagate);
    CFStringRef transfer = frame->color_trc == AVCOL_TRC_SMPTE2084 ? kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ :
        frame->color_trc == AVCOL_TRC_ARIB_STD_B67 ? kCVImageBufferTransferFunction_ITU_R_2100_HLG :
        frame->color_trc == AVCOL_TRC_BT709 ? kCVImageBufferTransferFunction_ITU_R_709_2 : NULL;
    if (transfer) CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, transfer, kCVAttachmentMode_ShouldPropagate);
    if (!_imageContext) {
      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (device) _imageContext = [CIContext contextWithMTLDevice:device options:@{kCIContextCacheIntermediates: @NO}];
    }
    if (!_imageContext) { CVPixelBufferRelease(target); return NULL; }
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    @try {
      CIImage *image = [CIImage imageWithCVPixelBuffer:source];
      [_imageContext render:image toCVPixelBuffer:target bounds:CGRectMake(0, 0, frame->width, frame->height) colorSpace:color];
    } @catch (NSException *exception) {
      CGColorSpaceRelease(color); CVPixelBufferRelease(target); return NULL;
    }
    CGColorSpaceRelease(color);
  } else {
    _scaler = sws_getCachedContext(_scaler, frame->width, frame->height, (AVPixelFormat)frame->format,
        frame->width, frame->height, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
    int space = matrix == AVCOL_SPC_SMPTE170M || matrix == AVCOL_SPC_BT470BG ? SWS_CS_ITU601 :
        matrix == AVCOL_SPC_SMPTE240M ? SWS_CS_SMPTE240M : matrix == AVCOL_SPC_FCC ? SWS_CS_FCC :
        matrix == AVCOL_SPC_BT2020_NCL || matrix == AVCOL_SPC_BT2020_CL ? SWS_CS_BT2020 : SWS_CS_ITU709;
    const int *coefficients = sws_getCoefficients(space);
    if (!_scaler || sws_setColorspaceDetails(_scaler, coefficients, frame->color_range == AVCOL_RANGE_JPEG,
        coefficients, 1, 0, 1 << 16, 1 << 16) < 0 || CVPixelBufferLockBaseAddress(target, 0) != kCVReturnSuccess) {
      CVPixelBufferRelease(target); return NULL;
    }
    uint8_t *planes[4] = {(uint8_t *)CVPixelBufferGetBaseAddress(target), NULL, NULL, NULL};
    int strides[4] = {(int)CVPixelBufferGetBytesPerRow(target), 0, 0, 0};
    int rows = sws_scale(_scaler, frame->data, frame->linesize, 0, frame->height, planes, strides);
    CVPixelBufferUnlockBaseAddress(target, 0);
    if (rows != frame->height) { CVPixelBufferRelease(target); return NULL; }
  }
  return target;
}
- (void)publishFrame {
  if (_disposed) return;
  uint64_t sequence = 0;
  AVFrame *frame = mc_acquire_frame_snapshot(_decoder, &sequence);
  if (!frame) return;
  {
    std::lock_guard<std::mutex> guard(_pixelMutex);
    if (_disposed) { mc_release_frame(frame); return; }
    if (_latestFrame) mc_release_frame(_latestFrame);
    _latestFrame = frame; _latestSequence = sequence;
  }
  if (!_notificationPending.exchange(true)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_notificationPending = false;
      if (!self->_disposed && self.textureId >= 0) [self.textures textureFrameAvailable:self.textureId];
    });
  }
}
- (int64_t)writePCM:(const uint8_t *)bytes length:(size_t)length {
  std::lock_guard<std::mutex> control(_audioControlMutex);
  if (_disposed || _audioPaused || _audioInterrupted || !_audioQueue) return 0;
  // A system clock also advances through underruns. Start a fresh timeline
  // when every buffer has returned and the previous submitted tail has played;
  // otherwise a late packet would be counted as played immediately on enqueue.
  bool allReturned;
  { std::lock_guard<std::mutex> guard(_audioMutex); allReturned = _audioBuffers.size() == 3; }
  if (_audioStarted && _audioFramesSubmitted && allReturned) {
    AudioTimeStamp time = {};
    if (AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL) == noErr &&
        (time.mFlags & kAudioTimeStampSampleTimeValid) &&
        time.mSampleTime - _audioClockOrigin >= (double)_audioFramesSubmitted) {
      AudioQueuePause(_audioQueue); AudioQueueReset(_audioQueue);
      _audioStarted = false;
    }
  }
  const uint64_t startFrames = _audioFramesSubmitted;
  length -= length % 4;
  size_t accepted = 0;
  while (accepted < length) {
    AudioQueueBufferRef buffer = NULL;
    {
      std::lock_guard<std::mutex> guard(_audioMutex);
      if (_audioBuffers.empty()) break;
      buffer = _audioBuffers.back(); _audioBuffers.pop_back();
    }
    size_t count = std::min<size_t>(length - accepted, buffer->mAudioDataBytesCapacity);
    count -= count % 4;
    memcpy(buffer->mAudioData, bytes + accepted, count); buffer->mAudioDataByteSize = (UInt32)count;
    OSStatus error = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
    if (error != noErr) { [self recycleAudioBuffer:buffer]; return accepted ? (int64_t)accepted : -1; }
    accepted += count; _audioFramesSubmitted += count / 4;
    if (!_audioStarted) {
      if (AudioQueueStart(_audioQueue, NULL) != noErr) return -1;
      // AudioQueueReset clears buffers, but its sample clock can keep running.
      // Map queue age to submitted frames; preserve the logical frame count
      // across underruns, while explicit pause/flush starts a new generation.
      AudioTimeStamp origin = {};
      _audioClockOrigin = AudioQueueGetCurrentTime(_audioQueue, NULL, &origin, NULL) == noErr &&
          (origin.mFlags & kAudioTimeStampSampleTimeValid) ? origin.mSampleTime - (double)startFrames : -(double)startFrames;
      _audioStarted = true;
    }
  }
  return (int64_t)accepted;
}
- (void)recycleAudioBuffer:(AudioQueueBufferRef)buffer {
  std::lock_guard<std::mutex> guard(_audioMutex);
  // Reset/stop may return all queued buffers. Keep each free buffer once.
  if (std::find(_audioBuffers.begin(), _audioBuffers.end(), buffer) == _audioBuffers.end())
    _audioBuffers.push_back(buffer);
}
- (void)setPaused:(BOOL)paused { mc_set_paused(_decoder, paused); }
- (void)pauseAudio:(BOOL)paused {
  std::lock_guard<std::mutex> control(_audioControlMutex);
  _audioPaused = paused;
  if (!_audioQueue || _disposed) return;
  if (paused) {
    AudioQueuePause(_audioQueue); AudioQueueReset(_audioQueue);
    _audioStarted = false; _audioFramesSubmitted = 0; ++_audioGeneration;
  }
#if TARGET_OS_IOS
  else if (_audioInterrupted) {
    NSError *error = nil;
    _audioInterrupted = ![AVAudioSession.sharedInstance setActive:YES error:&error];
  }
#endif
  // Start only after the first buffer is queued, avoiding an empty restart.
}
- (int32_t)audioState:(mc_audio_state *)state {
  std::lock_guard<std::mutex> control(_audioControlMutex);
  if (!_audioQueue || _disposed) return -1;
  AudioTimeStamp time = {};
  OSStatus result = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
  if (result == noErr && (time.mFlags & kAudioTimeStampSampleTimeValid) && time.mSampleTime < _audioClockOrigin) _audioClockOrigin = 0;
  uint64_t played = result == noErr && (time.mFlags & kAudioTimeStampSampleTimeValid) && time.mSampleTime > _audioClockOrigin
      ? std::min<uint64_t>(_audioFramesSubmitted, (uint64_t)(time.mSampleTime - _audioClockOrigin)) : 0;
  state->played_frames = played; state->queued_frames = _audioFramesSubmitted - played;
  state->generation = _audioGeneration;
  state->running = _audioStarted && !_audioPaused && !_audioInterrupted;
  return 0;
}
#if TARGET_OS_IOS
- (void)audioInterruption:(NSNotification *)notification {
  bool begin = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
  std::lock_guard<std::mutex> control(_audioControlMutex);
  _audioInterrupted = begin;
  if (!_audioQueue || _disposed) return;
  if (begin) {
    AudioQueuePause(_audioQueue); AudioQueueReset(_audioQueue);
    _audioStarted = false; _audioFramesSubmitted = 0; ++_audioGeneration;
  } else {
    bool resume = ([notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) != 0;
    NSError *error = nil;
    _audioInterrupted = !resume || ![AVAudioSession.sharedInstance setActive:YES error:&error];
  }
}
- (void)audioRouteChanged:(NSNotification *)notification {
  std::lock_guard<std::mutex> control(_audioControlMutex);
  if (!_audioQueue || _disposed) return;
  AudioQueuePause(_audioQueue); AudioQueueReset(_audioQueue);
  _audioStarted = false; _audioFramesSubmitted = 0; ++_audioGeneration;
}
#endif
- (void)closeAudio {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  {
    std::lock_guard<std::mutex> control(_audioControlMutex);
    if (_audioQueue) {
      AudioQueueStop(_audioQueue, true); AudioQueueDispose(_audioQueue, true); _audioQueue = NULL;
    }
  }
#if TARGET_OS_IOS
  if (_ownsAudioSession) {
    std::lock_guard<std::mutex> guard(MCAudioSessionMutex);
    _ownsAudioSession = false;
    if (--MCAudioSessionUsers == 0) [AVAudioSession.sharedInstance setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
  }
#endif
  std::lock_guard<std::mutex> guard(_audioMutex);
  _audioBuffers.clear();
}
- (void)close {
  if (_disposed.exchange(true)) return;
  [NSNotificationCenter.defaultCenter removeObserver:self];
  // Drain a raster-thread copy before freeing its decoder. New copies see
  // disposed; decoded callbacks also stop publishing before this barrier.
  { std::lock_guard<std::mutex> guard(_pixelMutex); }
  if (_decoder) { mc_destroy(_decoder); _decoder = NULL; }
  [self closeAudio];
  std::lock_guard<std::mutex> guard(_pixelMutex);
  if (_pixelBuffer) { CVPixelBufferRelease(_pixelBuffer); _pixelBuffer = NULL; }
  if (_latestFrame) { mc_release_frame(_latestFrame); _latestFrame = NULL; }
  if (_pixelPool) { CVPixelBufferPoolRelease(_pixelPool); _pixelPool = NULL; }
  sws_freeContext(_scaler); _scaler = NULL; _imageContext = nil;
}
- (void)dealloc { [self close]; }
@end

@interface MediaCodecPlugin ()
@property(nonatomic, strong) NSObject<FlutterTextureRegistry> *textures;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MCMediaOutput *> *outputs;
@property(nonatomic, strong) dispatch_queue_t worker;
@property(nonatomic) int64_t nextHandle;
@end

@implementation MediaCodecPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  MediaCodecPlugin *plugin = [[MediaCodecPlugin alloc] init];
#if TARGET_OS_OSX
  plugin.textures = registrar.textures;
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"media_codec" binaryMessenger:registrar.messenger];
#else
  plugin.textures = [registrar textures];
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"media_codec" binaryMessenger:[registrar messenger]];
#endif
  plugin.outputs = [NSMutableDictionary dictionary]; plugin.nextHandle = 1;
  plugin.worker = dispatch_queue_create("dev.scrcpyconnect.media-codec", DISPATCH_QUEUE_SERIAL);
  [registrar addMethodCallDelegate:plugin channel:channel];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  if ([call.method isEqualToString:@"createVideo"] || [call.method isEqualToString:@"createAudio"]) {
    BOOL audio = [call.method isEqualToString:@"createAudio"];
    MCMediaOutput *output = [[MCMediaOutput alloc] init];
    output.handle = self.nextHandle++; output.textures = self.textures;
    if (!audio) output.textureId = [self.textures registerTexture:output];
    self.outputs[@(output.handle)] = output;
    dispatch_async(self.worker, ^{
      BOOL ready = [output open:args audio:audio];
      if (!ready) [output close];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!ready) {
          [self.outputs removeObjectForKey:@(output.handle)];
          if (output.textureId >= 0) {
            [self.textures unregisterTexture:output.textureId]; output.textureId = -1;
          }
          result([FlutterError errorWithCode:@"media_codec_create" message:@"Unable to attach native media output" details:nil]);
          return;
        }
        result(@{@"handle": @(output.handle), @"textureId": @(output.textureId),
                 @"width": args[@"width"] ?: @0, @"height": args[@"height"] ?: @0,
                 @"decoderAddress": @((uintptr_t)output->_decoder),
                 @"nativeApi": @{@"getStatusAddress": @((uintptr_t)&mc_get_status),
                                  @"setPausedAddress": @((uintptr_t)&mc_set_paused),
                                  @"setVolumeAddress": @((uintptr_t)&mc_set_volume)}});
      });
    });
    return;
  }
  MCMediaOutput *output = self.outputs[args[@"handle"]];
  if (!output) {
    if ([call.method isEqualToString:@"dispose"]) result(nil);
    else result([FlutterError errorWithCode:@"media_codec_handle" message:@"Media output is no longer available" details:nil]);
    return;
  }
  if ([call.method isEqualToString:@"dispose"]) [self.outputs removeObjectForKey:args[@"handle"]];
  dispatch_async(self.worker, ^{
    id response = nil;
    if ([call.method isEqualToString:@"status"]) {
      mc_status status = {}; mc_get_status(output->_decoder, &status);
      response = @{@"width": @(status.width), @"height": @(status.height),
                   @"frameCount": @(status.frame_count), @"bytesWritten": @(status.bytes_written),
                   @"positionMs": @(status.position_us / 1000), @"nativeReady": @(status.native_ready != 0),
                   @"firstFrame": @(status.frame_count > 0), @"ended": @(status.ended != 0),
                   @"paused": @(status.paused != 0),
                   @"hardwareAccelerated": @(status.hardware_accelerated != 0),
                   @"decoderName": @(status.decoder_name), @"errorCode": @(status.error_code), @"error": @(status.error)};
    } else if ([call.method isEqualToString:@"setPaused"]) {
      [output setPaused:[args[@"paused"] boolValue]];
    } else if ([call.method isEqualToString:@"setVolume"]) {
      mc_set_volume(output->_decoder, [args[@"volume"] doubleValue]);
    } else if ([call.method isEqualToString:@"snapshot"]) {
      mc_image image = {};
      if (mc_copy_rgba_scaled(output->_decoder, [args[@"width"] unsignedIntValue], [args[@"height"] unsignedIntValue], &image) == 0) {
        NSMutableData *bytes = [NSMutableData dataWithLength:image.width * image.height * 4];
        for (uint32_t y = 0; y < image.height; ++y)
          memcpy((uint8_t *)bytes.mutableBytes + y * image.width * 4, image.rgba + y * image.stride, image.width * 4);
        response = @{@"width": @(image.width), @"height": @(image.height), @"rgba": [FlutterStandardTypedData typedDataWithBytes:bytes]};
        mc_image_free(&image);
      }
    } else if ([call.method isEqualToString:@"dispose"]) {
      [output close];
    } else response = FlutterMethodNotImplemented;
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([call.method isEqualToString:@"dispose"] && output.textureId >= 0) {
        [self.textures unregisterTexture:output.textureId]; output.textureId = -1;
      }
      result(response);
    });
  });
}
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  NSArray<MCMediaOutput *> *outputs = self.outputs.allValues;
  [self.outputs removeAllObjects];
  // Drain native/Rust producers before textures can be unregistered by engine teardown.
  dispatch_sync(self.worker, ^{ for (MCMediaOutput *output in outputs) [output close]; });
  for (MCMediaOutput *output in outputs) {
    if (output.textureId >= 0) {
      [self.textures unregisterTexture:output.textureId]; output.textureId = -1;
    }
  }
}
@end
