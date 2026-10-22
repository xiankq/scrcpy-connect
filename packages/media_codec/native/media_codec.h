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
typedef int32_t (*mc_attach_fn)(const uint8_t*, size_t, uint64_t, const mc_sink_v1*);
typedef int32_t (*mc_detach_fn)(const uint8_t*, size_t, uint64_t);
typedef struct mc_decoder mc_decoder;
/* frame_ready runs on the decode thread. Callbacks must not destroy the decoder.
 * pcm is stereo signed PCM16 LE at 48000 Hz, valid only during the callback.
 * Return actual bytes accepted by the system audio output, negative on error. */
typedef void (*mc_frame_ready_fn)(void*);
typedef int64_t (*mc_pcm_fn)(void*, const uint8_t*, size_t);
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
  char decoder_name[96];
  char error[192];
} mc_status;
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
MC_EXPORT void mc_release_frame(struct AVFrame*);
/* Synchronously detaches and drains Rust callbacks before releasing decoder. */
MC_EXPORT void mc_destroy(mc_decoder*);
#ifdef __cplusplus
}
#endif
#endif
