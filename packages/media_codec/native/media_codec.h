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
/* Packet bytes are borrowed for the duration of the callback. Returning 1 asks
 * the producer to retry the same packet; compressed interframes are never dropped. */
typedef struct mc_sink_v1 {
  uint32_t abi_version;
  uint32_t struct_size;
  void* context;
  int32_t (*event)(void*, uint32_t, uint64_t, uint32_t, uint32_t,
                   uint32_t, const uint8_t*, size_t, int64_t, uint32_t);
} mc_sink_v1;
/* v2 transfers an exclusive writable allocation, including at least 64 zero
 * padding bytes after size. Only return 0 transfers ownership. Retry/failure
 * leaves ownership with the producer. The decoder calls release exactly once.
 * set_waker transfers its context; release runs after the last wake call. */
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
/* frame_ready runs on the decode thread. Callbacks must not destroy the decoder.
 * pcm is stereo signed PCM16 LE at 48000 Hz, valid only during the callback.
 * Return actual bytes accepted by the system audio output, negative on error. */
typedef void (*mc_frame_ready_fn)(void*);
typedef int64_t (*mc_pcm_fn)(void*, const uint8_t*, size_t);
typedef struct mc_audio_state {
  uint64_t played_frames;
  uint64_t queued_frames;
  uint64_t generation; /* Changes whenever the platform playback clock resets. */
  int32_t running;
} mc_audio_state;
typedef void (*mc_audio_pause_fn)(void*, int32_t);
typedef int32_t (*mc_audio_state_fn)(void*, mc_audio_state*);
/* 1: platform verifies hardware component, 0: software, -1: unknown. */
typedef int32_t (*mc_hardware_kind_fn)(void*, const char* component);
typedef struct mc_config {
  uint32_t struct_size;
  uint32_t codec; /* 1 AVC,2 HEVC,3 AV1,4 VP8,5 VP9,100 PCM16LE */
  uint32_t width;
  uint32_t height;
  uint64_t generation;
  void* user;
  mc_frame_ready_fn frame_ready;
  mc_pcm_fn pcm;
  const char* hardware_device; /* null: platform default, "none": software */
  void* native_window; /* Android ANativeWindow; caller retains until destroy */
  mc_audio_pause_fn audio_pause; /* Synchronous pause/flush, serialized with pcm. */
  mc_audio_state_fn audio_state; /* Actual device clock and pending frames. */
  mc_hardware_kind_fn hardware_kind;
  mc_frame_ready_fn audio_close; /* Runs once on the PCM worker before it exits. */
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
  int32_t hardware_verification; /* -1 unknown, 0 software, 1 hardware component */
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
/* Android only: synchronously swaps a retained ANativeWindow without changing
 * decoder identity. Caller retains new window until the next swap/destroy and
 * releases the previous window only after this call returns. Never call from
 * frame_ready/pcm callbacks. Null temporarily removes the presentation target. */
MC_EXPORT void mc_set_native_window(mc_decoder*, void* native_window);
/* Copies latest frame for CPU texture fallback or explicit snapshot. Free using
 * mc_image_free. Conversion is lazy: GPU adapters use mc_acquire_frame instead. */
MC_EXPORT int32_t mc_copy_rgba(mc_decoder*, mc_image*);
MC_EXPORT int32_t mc_copy_rgba_scaled(mc_decoder*, uint32_t max_width,
                                     uint32_t max_height, mc_image*);
MC_EXPORT void mc_image_free(mc_image*);
/* Returns an av_frame_clone of latest decoded frame. Release via
 * mc_release_frame. Opaque declaration keeps FFmpeg headers out of platform ABI. */
struct AVFrame;
MC_EXPORT struct AVFrame* mc_acquire_frame(mc_decoder*);
/* Frame and sequence are acquired under the same lock. A platform must never
 * combine a frame from one acquisition with dimensions from another. */
MC_EXPORT struct AVFrame* mc_acquire_frame_snapshot(mc_decoder*, uint64_t* sequence);
MC_EXPORT int32_t mc_copy_frame_rgba(struct AVFrame*, mc_image*);
MC_EXPORT int32_t mc_copy_frame_bgra(struct AVFrame*, mc_image*);
/* Successful platform texture preparation is distinct from decoding. It does
 * not prove subsequent engine import, composition or display consumption. */
MC_EXPORT void mc_report_present(mc_decoder*, uint64_t sequence,
                                 const char* path, const char* error);
MC_EXPORT void mc_release_frame(struct AVFrame*);
/* Synchronously detaches and drains Rust callbacks before releasing decoder. */
MC_EXPORT void mc_destroy(mc_decoder*);
#ifdef __cplusplus
}
#endif
#endif
