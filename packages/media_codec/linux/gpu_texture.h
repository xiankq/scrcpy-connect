#ifndef MEDIA_CODEC_LINUX_GPU_TEXTURE_H
#define MEDIA_CODEC_LINUX_GPU_TEXTURE_H
#include <cstdint>
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <vector>
struct AVFrame;
/* FFmpeg 将 VA-API surface 导出为 DRM PRIME，再以 Y/UV EGL 图像导入。
 * 驱动或格式不支持时返回 false，交由 CPU 回退。 */
class McLinuxGpuTexture {
public:
  bool render(AVFrame *frame, GLuint output);
  // CPU 回退重建输出后，使存储缓存失效。
  void storage_changed() { width_ = height_ = 0; }
  void release_shared_resources();

private:
  struct Pending {
    GLsync fence = nullptr;
    AVFrame *frame = nullptr;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLImageKHR images[2] = {EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR};
    GLuint textures[3]{};
    void *cuda_context = nullptr;
    void *cuda_resources[2]{};
  };
  void reap(bool wait);
  std::vector<Pending> pending_;
  GLuint program_ = 0;
  GLuint software_textures_[3]{};
  int software_width_ = 0, software_height_ = 0;
  bool software_planar_ = false;
  int width_ = 0, height_ = 0;
};
#endif
