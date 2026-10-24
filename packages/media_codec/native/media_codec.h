#ifndef MEDIA_CODEC_NATIVE_H
#define MEDIA_CODEC_NATIVE_H
#include <stddef.h>
#include <stdint.h>
#if defined(_WIN32)
#define MC_EXPORT __declspec(dllexport)
#else
#define MC_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* 数据包字节只在回调期间借用；返回 1 要求生产者重试同一数据包，不丢弃压缩帧间预测包。 */
typedef struct mc_sink_v1 {
  uint32_t abi_version;
  uint32_t struct_size;
  void* context;
  int32_t (*event)(void*, uint32_t, uint64_t, uint32_t, uint32_t,
                   uint32_t, const uint8_t*, size_t, int64_t, uint32_t);
} mc_sink_v1;
/* v2 转移独占可写存储，size 后至少保留 64 个零填充字节。
 * 仅返回 0 才转移所有权；重试或失败时生产者继续持有。解码器恰好调用一次 release。
 * set_waker 转移其上下文，最后一次 wake 调用结束后才执行 release。 */
typedef void (*mc_release_fn)(void*);
typedef void (*mc_wake_fn)(void*);
typedef struct mc_sink_v2 {
  mc_sink_v1 base;
  int32_t (*event_owned)(void*, uint32_t, uint64_t, uint32_t, uint32_t,
      uint32_t, uint8_t*, size_t, size_t, void*, mc_release_fn, int64_t, uint32_t);
  void (*set_waker)(void*, void*, mc_wake_fn, mc_release_fn);
} mc_sink_v2;
typedef int32_t (*mc_attach_fn)(const uint8_t*, size_t, uint64_t, const mc_sink_v1*);
typedef int32_t (*mc_detach_fn)(const uint8_t*, size_t, uint64_t);
typedef struct mc_decoder mc_decoder;
/* frame_ready 在解码线程执行，回调不能销毁解码器。
 * pcm 是 48000 Hz 双声道有符号 PCM16 LE，仅在回调期间有效。
 * 返回系统音频输出实际接受的字节数，负值表示错误。 */
typedef void (*mc_frame_ready_fn)(void*);
typedef int64_t (*mc_pcm_fn)(void*, const uint8_t*, size_t);
typedef struct mc_audio_state {
  uint64_t played_frames;
  uint64_t queued_frames;
  uint64_t generation; /* 平台播放时钟重置时更新。 */
  int32_t running;
} mc_audio_state;
typedef void (*mc_audio_pause_fn)(void*, int32_t);
typedef int32_t (*mc_audio_state_fn)(void*, mc_audio_state*);
/* 1：平台核验为硬件组件；0：软件；-1：未知。 */
typedef int32_t (*mc_hardware_kind_fn)(void*, const char* component);
typedef struct mc_config {
  uint32_t struct_size;
  uint32_t codec; /* 编码标识：1 AVC、2 HEVC、3 AV1、4 VP8、5 VP9、100 PCM16LE。 */
  uint32_t width;
  uint32_t height;
  uint64_t generation;
  void* user;
  mc_frame_ready_fn frame_ready;
  mc_pcm_fn pcm;
  const char* hardware_device; /* null 使用平台默认设备，"none" 使用软件解码。 */
  void* native_window; /* Android ANativeWindow；调用方持有至解码器销毁。 */
  mc_audio_pause_fn audio_pause; /* 同步暂停及清空，与 pcm 回调串行执行。 */
  mc_audio_state_fn audio_state; /* 实际设备时钟及待播放帧数。 */
  mc_hardware_kind_fn hardware_kind;
  mc_frame_ready_fn audio_close; /* 在 PCM 工作线程退出前调用一次。 */
} mc_config;
typedef struct mc_status {
  uint32_t width;
  uint32_t height;
  uint64_t frame_count;
  uint64_t bytes_written;
  int64_t position_us;
  int32_t hardware_accelerated;
  int32_t native_ready;
  int32_t ended;
  int32_t error_code;
  int32_t paused;
  char decoder_name[96];
  char error[192];
  uint64_t presented_frame_count;
  uint64_t presented_sequence;
  char presentation_path[96];
  char presentation_error[192];
  uint64_t audio_played_frames;
  uint64_t audio_queued_frames;
  uint64_t audio_dropped_frames;
  int32_t backend_hardware_frames;
  int32_t hardware_verification; /* -1 未知，0 软件，1 硬件组件。 */
} mc_status;
typedef void mc_get_status_call(mc_decoder*, mc_status*);
typedef void mc_set_paused_call(mc_decoder*, int32_t);
typedef void mc_set_volume_call(mc_decoder*, double);
typedef mc_get_status_call* mc_get_status_fn;
typedef mc_set_paused_call* mc_set_paused_fn;
typedef mc_set_volume_call* mc_set_volume_fn;
typedef struct mc_image {
  uint32_t width;
  uint32_t height;
  size_t stride;
  size_t size;
  uint8_t* rgba;
} mc_image;
MC_EXPORT mc_decoder* mc_create(const mc_config* config);
MC_EXPORT int32_t mc_attach(mc_decoder*, const char* source_id,
                            uintptr_t attach_address, uintptr_t detach_address);
MC_EXPORT void mc_get_status(mc_decoder*, mc_status*);
MC_EXPORT void mc_set_paused(mc_decoder*, int32_t paused);
MC_EXPORT void mc_set_volume(mc_decoder*, double volume);
/* 仅 Android：同步替换保留的 ANativeWindow，不改变解码器身份。
 * 调用方持有新窗口直到下次替换或销毁，本调用返回后才释放旧窗口。
 * 不能从 frame_ready/pcm 回调调用；空指针暂时移除呈现目标。 */
MC_EXPORT void mc_set_native_window(mc_decoder*, void* native_window);
/* 为 CPU 纹理回退或明确截图复制最新帧，使用 mc_image_free 释放。
 * 转换按需执行；GPU adapter 使用 mc_acquire_frame。 */
MC_EXPORT int32_t mc_copy_rgba(mc_decoder*, mc_image*);
MC_EXPORT int32_t mc_copy_rgba_scaled(mc_decoder*, uint32_t max_width,
                                     uint32_t max_height, mc_image*);
MC_EXPORT void mc_image_free(mc_image*);
/* 返回最新解码帧的 av_frame_clone，使用 mc_release_frame 释放。
 * 不透明声明避免平台 ABI 引入 FFmpeg 头文件。 */
struct AVFrame;
MC_EXPORT struct AVFrame* mc_acquire_frame(mc_decoder*);
/* 在同一把锁内取得帧及序号；平台不能将一次获取的帧与另一次获取的尺寸混用。 */
MC_EXPORT struct AVFrame* mc_acquire_frame_snapshot(mc_decoder*, uint64_t* sequence);
MC_EXPORT int32_t mc_copy_frame_rgba(struct AVFrame*, mc_image*);
MC_EXPORT int32_t mc_copy_frame_bgra(struct AVFrame*, mc_image*);
/* 平台纹理准备完成与解码完成分别取证，不证明后续引擎导入、合成或显示消费。 */
MC_EXPORT void mc_report_present(mc_decoder*, uint64_t sequence,
                                 const char* path, const char* error);
MC_EXPORT void mc_release_frame(struct AVFrame*);
/* 释放解码器前同步分离并排空 Rust 回调。 */
MC_EXPORT void mc_destroy(mc_decoder*);
#ifdef __cplusplus
}
#endif
#endif
