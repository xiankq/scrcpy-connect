#ifndef MEDIA_CODEC_LINUX_GPU_TEXTURE_H
#define MEDIA_CODEC_LINUX_GPU_TEXTURE_H
#include <cstdint>
#include <epoxy/gl.h>
struct AVFrame;
/* VA-API surfaces are exported by FFmpeg as DRM PRIME and imported as Y/UV
 * EGL images. Unsupported drivers/formats return false for the CPU fallback. */
class McLinuxGpuTexture {
 public:
  bool render(AVFrame* frame,GLuint output);
 private:
  GLuint program_=0,vao_=0,framebuffer_=0;
  int width_=0,height_=0;
};
#endif
