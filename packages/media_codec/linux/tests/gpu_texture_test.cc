// Standalone EGL regression: links the production importer, no Flutter mocks.
#include "../gpu_texture.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <cstring>
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
}

static AVFrame *frame(int size, AVPixelFormat format, AVColorSpace colorspace) {
  auto *f = av_frame_alloc();
  assert(f);
  f->width = f->height = size;
  f->format = format;
  f->colorspace = colorspace;
  f->color_range = AVCOL_RANGE_MPEG;
  assert(av_frame_get_buffer(f, 32) == 0);
  for (int p = 0; p < (format == AV_PIX_FMT_NV12 ? 2 : 3); ++p)
    for (int row = 0; row < (p ? size / 2 : size); ++row) {
      auto *bytes = f->data[p] + row * f->linesize[p];
      if (p && format == AV_PIX_FMT_NV12)
        for (int col = 0; col < size; col += 2) {
          bytes[col] = 80;
          bytes[col + 1] = 200;
        }
      else
        memset(bytes, p ? (p == 1 ? 80 : 200) : 128, p ? size / 2 : size);
    }
  return f;
}
static std::array<uint8_t, 4> pixel(GLuint texture, int expected_size) {
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  GLuint fbo;
  glGenFramebuffers(1, &fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         texture, 0);
  assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
  glBindTexture(GL_TEXTURE_2D, texture);
  GLint size = 0;
  glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &size);
  assert(size == expected_size);
  std::array<uint8_t, 4> result{};
  glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, result.data());
  assert(glGetError() == GL_NO_ERROR);
  glDeleteFramebuffers(1, &fbo);
  return result;
}
int main(int argc, char **) {
  EGLDisplay display = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA,
                                                EGL_DEFAULT_DISPLAY, nullptr);
  assert(display != EGL_NO_DISPLAY);
  assert(eglInitialize(display, nullptr, nullptr));
  assert(eglBindAPI(EGL_OPENGL_API));
  EGLint attrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE,
                    EGL_PBUFFER_BIT, EGL_NONE};
  EGLConfig config;
  EGLint count;
  assert(eglChooseConfig(display, attrs, &config, 1, &count) && count);
  EGLint context_attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3,
                            EGL_CONTEXT_MINOR_VERSION, 3, EGL_NONE};
  EGLContext context =
      eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
  assert(context != EGL_NO_CONTEXT);
  assert(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context));
  printf("GL renderer: %s\n", glGetString(GL_RENDERER));
  McLinuxGpuTexture renderer;
  GLuint texture;
  glGenTextures(1, &texture);
  auto *f = frame(4, AV_PIX_FMT_YUV420P, AVCOL_SPC_BT709);
  assert(renderer.render(f, texture));
  auto reference = pixel(texture, 4);
  assert(reference[0] > 240 && reference[1] > 95 && reference[1] < 115 &&
         reference[2] > 20 && reference[2] < 45 && reference[3] == 255);
  f->colorspace = AVCOL_SPC_UNSPECIFIED;
  assert(renderer.render(f, texture));
  assert(pixel(texture, 4) == reference);
  av_frame_free(&f);
  f = frame(4, AV_PIX_FMT_NV12, AVCOL_SPC_BT709);
  assert(renderer.render(f, texture));
  assert(pixel(texture, 4) == reference);

  // A CPU fallback may redefine this very same GL name to a different size.
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE,
               nullptr);
  renderer.storage_changed();
  assert(renderer.render(f, texture));
  assert(pixel(texture, 4) == reference);

  // Simulate host state that previously interpreted CPU addresses as offsets,
  // disabled drawing, and overwrote the host's distinct READ binding.
  GLuint fbos[2], pbo;
  glGenFramebuffers(2, fbos);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbos[0]);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbos[1]);
  glGenBuffers(1, &pbo);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
  glBufferData(GL_PIXEL_UNPACK_BUFFER, 512, nullptr, GL_STREAM_DRAW);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 8);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 9);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 1);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 1);
  glEnable(GL_RASTERIZER_DISCARD);
  glEnable(0); // Deliberately leave an unrelated GL_INVALID_ENUM.
  assert(renderer.render(f, texture));
  GLint saved;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saved);
  assert(saved == static_cast<GLint>(fbos[0]));
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved);
  assert(saved == static_cast<GLint>(fbos[1]));
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &saved);
  assert(saved == static_cast<GLint>(pbo));
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, &saved);
  assert(saved == 1);
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &saved);
  assert(saved == 1);
  assert(glIsEnabled(GL_RASTERIZER_DISCARD));
  glDisable(GL_RASTERIZER_DISCARD);
  assert(pixel(texture, 4) == reference);
  glDeleteBuffers(1, &pbo);
  glDeleteFramebuffers(2, fbos);
  av_frame_free(&f);
  if (argc > 1) {
    AVBufferRef *device = nullptr;
    assert(av_hwdevice_ctx_create(&device, AV_HWDEVICE_TYPE_VAAPI,
                                  "/dev/dri/renderD128", nullptr, 0) == 0);
    AVBufferRef *frames = av_hwframe_ctx_alloc(device);
    assert(frames);
    auto *info = reinterpret_cast<AVHWFramesContext *>(frames->data);
    info->format = AV_PIX_FMT_VAAPI;
    info->sw_format = AV_PIX_FMT_NV12;
    info->width = info->height = 64;
    assert(av_hwframe_ctx_init(frames) == 0);
    auto *cpu = frame(64, AV_PIX_FMT_NV12, AVCOL_SPC_BT709);
    for (int i = 0; i < 12; ++i) {
      auto *gpu = av_frame_alloc();
      assert(gpu);
      assert(av_hwframe_get_buffer(frames, gpu, 0) == 0);
      assert(av_hwframe_transfer_data(gpu, cpu, 0) == 0);
      assert(av_frame_copy_props(gpu, cpu) == 0);
      assert(renderer.render(gpu, texture));
      // Let the importer retain all borrowed surfaces safely across iterations.
      av_frame_free(&gpu);
    }
    assert(pixel(texture, 64) == reference);
    renderer.release_shared_resources();
    av_frame_free(&cpu);
    av_buffer_unref(&frames);
    av_buffer_unref(&device);
    puts("PASS: VAAPI DMA-BUF import and retained-surface fences");
  }
  renderer.release_shared_resources();
  glDeleteTextures(1, &texture);
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroyContext(display, context);
  eglTerminate(display);
  puts("PASS: YUV/NV12 conversion, BT709 default, fallback resize, GL "
       "isolation");
}
