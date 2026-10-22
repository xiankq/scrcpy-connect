#import "MediaCodecPlugin.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <TargetConditionals.h>
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <chrono>
#include <cstring>
#include <mutex>
#include <vector>
#include "media_codec.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}

@interface MCMediaOutput : NSObject <FlutterTexture> {
 @public
  mc_decoder *_decoder;
  CVPixelBufferRef _pixelBuffer;
  std::mutex _pixelMutex;
  std::mutex _audioMutex;
  std::condition_variable _audioAvailable;
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
@end

static void MCFrame(void *context) { [(__bridge MCMediaOutput *)context publishFrame]; }
static int64_t MCPCM(void *context, const uint8_t *bytes, size_t length) {
  return [(__bridge MCMediaOutput *)context writePCM:bytes length:length];
}
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
    _textureId = -1; _disposed = false; _notificationPending = false; _audioPaused = false;
  }
  return self;
}
- (BOOL)open:(NSDictionary *)arguments audio:(BOOL)audio {
  if (audio) {
#if TARGET_OS_IOS
    NSError *sessionError = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError] ||
        ![session setActive:YES error:&sessionError]) return NO;
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
  _decoder = mc_create(&config);
  NSString *source = arguments[@"sourceId"];
  if (!_decoder || ![source isKindOfClass:NSString.class]) return NO;
  return mc_attach(_decoder, source.UTF8String, [arguments[@"attachAddress"] unsignedLongLongValue],
                   [arguments[@"detachAddress"] unsignedLongLongValue]) == 0;
}
- (CVPixelBufferRef)copyPixelBuffer {
  std::lock_guard<std::mutex> guard(_pixelMutex);
  return _pixelBuffer ? CVPixelBufferRetain(_pixelBuffer) : NULL;
}
- (void)publishFrame {
  if (_disposed) return;
  AVFrame *frame = mc_acquire_frame(_decoder);
  CVPixelBufferRef next = NULL;
  if (frame && frame->format == AV_PIX_FMT_VIDEOTOOLBOX && frame->data[3]) {
    // VideoToolbox's IOSurface-backed buffer can be imported by Flutter's renderer.
    CVPixelBufferRef hardwareBuffer = (CVPixelBufferRef)frame->data[3];
    OSType format = CVPixelBufferGetPixelFormatType(hardwareBuffer);
    if (format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
        format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) next = CVPixelBufferRetain(hardwareBuffer);
  }
  if (!next) {
    mc_image image = {};
    if (mc_copy_rgba(_decoder, &image)) {
      NSDictionary *attributes = @{ (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
                                    (id)kCVPixelBufferMetalCompatibilityKey: @YES };
      if (CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
          kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &next) == kCVReturnSuccess) {
        CVPixelBufferLockBaseAddress(next, 0);
        uint8_t *target = (uint8_t *)CVPixelBufferGetBaseAddress(next);
        size_t stride = CVPixelBufferGetBytesPerRow(next);
        for (uint32_t y = 0; y < image.height; ++y) {
          const uint8_t *row = image.rgba + y * image.stride;
          uint8_t *out = target + y * stride;
          for (uint32_t x = 0; x < image.width; ++x) {
            out[x * 4] = row[x * 4 + 2]; out[x * 4 + 1] = row[x * 4 + 1];
            out[x * 4 + 2] = row[x * 4]; out[x * 4 + 3] = row[x * 4 + 3];
          }
        }
        CVPixelBufferUnlockBaseAddress(next, 0);
      }
      mc_image_free(&image);
    }
  }
  mc_release_frame(frame);
  if (!next) return;
  {
    std::lock_guard<std::mutex> guard(_pixelMutex);
    if (_pixelBuffer) CVPixelBufferRelease(_pixelBuffer);
    _pixelBuffer = next;
  }
  if (!_notificationPending.exchange(true)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_notificationPending = false;
      if (!self->_disposed && self.textureId >= 0) [self.textures textureFrameAvailable:self.textureId];
    });
  }
}
- (int64_t)writePCM:(const uint8_t *)bytes length:(size_t)length {
  if (_disposed || _audioPaused || !_audioQueue) return 0;
  length -= length % 4;
  size_t accepted = 0;
  auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(80);
  while (accepted < length && !_disposed && !_audioPaused) {
    AudioQueueBufferRef buffer = NULL;
    {
      std::unique_lock<std::mutex> guard(_audioMutex);
      if (!_audioAvailable.wait_until(guard, deadline, [&]{ return _disposed || _audioPaused || !_audioBuffers.empty(); })) break;
      if (_disposed || _audioPaused) break;
      buffer = _audioBuffers.back(); _audioBuffers.pop_back();
    }
    size_t count = std::min<size_t>(length - accepted, buffer->mAudioDataBytesCapacity);
    memcpy(buffer->mAudioData, bytes + accepted, count); buffer->mAudioDataByteSize = (UInt32)count;
    OSStatus error = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
    if (error != noErr) { [self recycleAudioBuffer:buffer]; return -1; }
    if (!_audioStarted) {
      if (AudioQueueStart(_audioQueue, NULL) != noErr) return -1;
      _audioStarted = true;
    }
    accepted += count;
  }
  return (int64_t)accepted;
}
- (void)recycleAudioBuffer:(AudioQueueBufferRef)buffer {
  std::lock_guard<std::mutex> guard(_audioMutex);
  _audioBuffers.push_back(buffer);
  _audioAvailable.notify_one();
}
- (void)setPaused:(BOOL)paused {
  mc_set_paused(_decoder, paused);
  if (_audioQueue) {
    _audioPaused = paused; _audioAvailable.notify_all();
    if (paused) {
      AudioQueuePause(_audioQueue);
      AudioQueueReset(_audioQueue);
    } else AudioQueueStart(_audioQueue, NULL);
  }
}
- (void)close {
  if (_disposed.exchange(true)) return;
  _audioAvailable.notify_all();
  if (_decoder) { mc_destroy(_decoder); _decoder = NULL; }
  if (_audioQueue) {
    AudioQueueStop(_audioQueue, true); AudioQueueDispose(_audioQueue, true); _audioQueue = NULL;
  }
  std::lock_guard<std::mutex> guard(_pixelMutex);
  if (_pixelBuffer) { CVPixelBufferRelease(_pixelBuffer); _pixelBuffer = NULL; }
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
          if (output.textureId >= 0) [self.textures unregisterTexture:output.textureId];
          result([FlutterError errorWithCode:@"media_codec_create" message:@"Unable to attach native media output" details:nil]);
          return;
        }
        result(@{@"handle": @(output.handle), @"textureId": @(output.textureId),
                 @"width": args[@"width"] ?: @0, @"height": args[@"height"] ?: @0});
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
                   @"hardwareAccelerated": @(status.hardware_accelerated != 0),
                   @"decoderName": @(status.decoder_name), @"errorCode": @(status.error_code), @"error": @(status.error)};
    } else if ([call.method isEqualToString:@"setPaused"]) {
      [output setPaused:[args[@"paused"] boolValue]];
    } else if ([call.method isEqualToString:@"setVolume"]) {
      mc_set_volume(output->_decoder, [args[@"volume"] doubleValue]);
    } else if ([call.method isEqualToString:@"snapshot"]) {
      mc_image image = {};
      if (mc_copy_rgba_scaled(output->_decoder, [args[@"width"] unsignedIntValue], [args[@"height"] unsignedIntValue], &image)) {
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
      if ([call.method isEqualToString:@"dispose"] && output.textureId >= 0)
        [self.textures unregisterTexture:output.textureId];
      result(response);
    });
  });
}
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  NSArray<MCMediaOutput *> *outputs = self.outputs.allValues;
  [self.outputs removeAllObjects];
  // Drain native/Rust producers before textures can be unregistered by engine teardown.
  dispatch_sync(self.worker, ^{ for (MCMediaOutput *output in outputs) [output close]; });
  for (MCMediaOutput *output in outputs)
    if (output.textureId >= 0) [self.textures unregisterTexture:output.textureId];
}
@end
