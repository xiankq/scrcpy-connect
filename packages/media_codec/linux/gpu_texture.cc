#include "gpu_texture.h"
#include <algorithm>
#include <dlfcn.h>
#include <epoxy/egl.h>
#include <limits>
#include <vector>
extern "C" {
#include <ffnvcodec/dynlink_cuda.h>
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_cuda.h>
#include <libavutil/hwcontext_drm.h>
}
namespace {
// Runtime-loaded CUDA/GL interop keeps systems without NVIDIA usable. Copies
// NV12 planes device-to-device; no host pixels or CUDA SDK dependency.
class CudaInterop {
public:
  CudaInterop() {
    library_ = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!library_)
      return;
    push = load<tcuCtxPushCurrent_v2>("cuCtxPushCurrent_v2");
    pop = load<tcuCtxPopCurrent_v2>("cuCtxPopCurrent_v2");
    reg = load<tcuGraphicsGLRegisterImage>("cuGraphicsGLRegisterImage");
    unreg = load<tcuGraphicsUnregisterResource>("cuGraphicsUnregisterResource");
    map = load<tcuGraphicsMapResources>("cuGraphicsMapResources");
    unmap = load<tcuGraphicsUnmapResources>("cuGraphicsUnmapResources");
    array = load<tcuGraphicsSubResourceGetMappedArray>(
        "cuGraphicsSubResourceGetMappedArray");
    copy = load<tcuMemcpy2DAsync_v2>("cuMemcpy2DAsync_v2");
    sync = load<tcuStreamSynchronize>("cuStreamSynchronize");
  }
  ~CudaInterop() {
    if (library_)
      dlclose(library_);
  }
  bool upload(AVFrame *frame, GLuint *textures, void **resources,
              void **context) {
    if (!push || !pop || !reg || !unreg || !map || !unmap || !array || !copy ||
        !sync)
      return false;
    if (!frame->data[0] || !frame->data[1] ||
        frame->linesize[0] < frame->width ||
        frame->linesize[1] < ((frame->width + 1) / 2) * 2)
      return false;
    auto *frames =
        reinterpret_cast<AVHWFramesContext *>(frame->hw_frames_ctx->data);
    auto *device =
        reinterpret_cast<AVCUDADeviceContext *>(frames->device_ctx->hwctx);
    if (!device || push(device->cuda_ctx) != CUDA_SUCCESS)
      return false;
    CUgraphicsResource handles[2]{};
    bool okay = true, mapped = false;
    for (int i = 0; i < 2; ++i)
      if (reg(&handles[i], textures[i], GL_TEXTURE_2D, 2) != CUDA_SUCCESS) {
        okay = false;
        break;
      }
    if (okay) {
      mapped = map(2, handles, device->stream) == CUDA_SUCCESS;
      okay = mapped;
    }
    for (int i = 0; okay && i < 2; ++i) {
      CUDA_MEMCPY2D transfer{};
      transfer.srcMemoryType = CU_MEMORYTYPE_DEVICE;
      transfer.srcDevice = reinterpret_cast<CUdeviceptr>(frame->data[i]);
      transfer.srcPitch = frame->linesize[i];
      transfer.dstMemoryType = CU_MEMORYTYPE_ARRAY;
      transfer.WidthInBytes = i ? ((frame->width + 1) / 2) * 2 : frame->width;
      transfer.Height = i ? (frame->height + 1) / 2 : frame->height;
      okay = array(&transfer.dstArray, handles[i], 0, 0) == CUDA_SUCCESS &&
             copy(&transfer, device->stream) == CUDA_SUCCESS;
    }
    if (mapped && unmap(2, handles, device->stream) != CUDA_SUCCESS)
      okay = false;
    if (okay) {
      *context = device->cuda_ctx;
      for (int i = 0; i < 2; ++i)
        resources[i] = handles[i];
    } else {
      // Only the error path blocks; successful GL draws wait on CUDA unmap
      // implicitly, and their GL fence retains both registration and source.
      sync(device->stream);
      for (auto handle : handles)
        if (handle)
          unreg(handle);
    }
    CUcontext previous;
    pop(&previous);
    return okay;
  }
  void release(void *context, void **resources) {
    if (!context || push(static_cast<CUcontext>(context)) != CUDA_SUCCESS)
      return;
    for (int i = 0; i < 2; ++i)
      if (resources[i])
        unreg(static_cast<CUgraphicsResource>(resources[i]));
    CUcontext previous;
    pop(&previous);
  }

private:
  template <class T> T *load(const char *name) {
    return reinterpret_cast<T *>(dlsym(library_, name));
  }
  void *library_ = nullptr;
  tcuCtxPushCurrent_v2 *push = nullptr;
  tcuCtxPopCurrent_v2 *pop = nullptr;
  tcuGraphicsGLRegisterImage *reg = nullptr;
  tcuGraphicsUnregisterResource *unreg = nullptr;
  tcuGraphicsMapResources *map = nullptr;
  tcuGraphicsUnmapResources *unmap = nullptr;
  tcuGraphicsSubResourceGetMappedArray *array = nullptr;
  tcuMemcpy2DAsync_v2 *copy = nullptr;
  tcuStreamSynchronize *sync = nullptr;
};
CudaInterop &cuda() {
  static CudaInterop value;
  return value;
}
constexpr uint32_t fourcc(char a, char b, char c, char d) {
  return uint32_t(a) | (uint32_t(b) << 8) | (uint32_t(c) << 16) |
         (uint32_t(d) << 24);
}
GLuint shader(GLenum type, const char *source) {
  GLuint result = glCreateShader(type);
  glShaderSource(result, 1, &source, nullptr);
  glCompileShader(result);
  GLint okay = 0;
  glGetShaderiv(result, GL_COMPILE_STATUS, &okay);
  if (!okay) {
    glDeleteShader(result);
    return 0;
  }
  return result;
}
GLuint program() {
  bool desktop = epoxy_is_desktop_gl();
  const char *vertexDesktop = "#version 130\nout vec2 uv;void main(){vec2 "
                              "p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=p;"
                              "gl_Position=vec4(p*2.0-1.0,0.0,1.0);}";
  const char *vertexEs = "#version 300 es\nout vec2 uv;void main(){vec2 "
                         "p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=p;gl_"
                         "Position=vec4(p*2.0-1.0,0.0,1.0);}";
  const char *fragmentDesktop =
      "#version 130\nin vec2 uv;out vec4 color;uniform sampler2D "
      "yPlane;uniform sampler2D uvPlane;uniform vec3 offset;uniform mat3 "
      "matrix;uniform sampler2D vPlane;uniform int planar;void main(){vec3 "
      "yuv=vec3(texture(yPlane,uv).r,texture(uvPlane,uv).r,planar!=0?texture("
      "vPlane,uv).r:texture(uvPlane,uv).g)+offset;color=vec4("
      "matrix*yuv,1.0);}";
  const char *fragmentEs =
      "#version 300 es\nprecision highp float;in vec2 uv;out vec4 "
      "color;uniform sampler2D yPlane;uniform sampler2D uvPlane;uniform vec3 "
      "offset;uniform mat3 matrix;uniform sampler2D vPlane;uniform int "
      "planar;void main(){vec3 "
      "yuv=vec3(texture(yPlane,uv).r,texture(uvPlane,uv).r,planar!=0?texture("
      "vPlane,uv).r:texture(uvPlane,uv).g)+offset;color=vec4("
      "matrix*yuv,1.0);}";
  GLuint vertex = shader(GL_VERTEX_SHADER, desktop ? vertexDesktop : vertexEs),
         fragment =
             shader(GL_FRAGMENT_SHADER, desktop ? fragmentDesktop : fragmentEs);
  if (!vertex || !fragment) {
    if (vertex)
      glDeleteShader(vertex);
    if (fragment)
      glDeleteShader(fragment);
    return 0;
  }
  GLuint result = glCreateProgram();
  glAttachShader(result, vertex);
  glAttachShader(result, fragment);
  glLinkProgram(result);
  glDeleteShader(vertex);
  glDeleteShader(fragment);
  GLint okay = 0;
  glGetProgramiv(result, GL_LINK_STATUS, &okay);
  if (!okay) {
    glDeleteProgram(result);
    return 0;
  }
  return result;
}
} // namespace
void McLinuxGpuTexture::reap(bool wait) {
  while (!pending_.empty()) {
    auto &p = pending_.front();
    auto result = glClientWaitSync(p.fence, GL_SYNC_FLUSH_COMMANDS_BIT,
                                   wait ? GL_TIMEOUT_IGNORED : 0);
    if (result == GL_TIMEOUT_EXPIRED)
      break;
    if (result == GL_WAIT_FAILED)
      glFinish(); // Exception path: never recycle a potentially active surface.
    glDeleteSync(p.fence);
    cuda().release(p.cuda_context, p.cuda_resources);
    glDeleteTextures(3, p.textures);
    for (auto image : p.images)
      if (image != EGL_NO_IMAGE_KHR)
        eglDestroyImageKHR(p.display, image);
    av_frame_free(&p.frame);
    pending_.erase(pending_.begin());
  }
}
void McLinuxGpuTexture::release_shared_resources() {
  // Sync objects and texture/program names are shared by GDK contexts.
  reap(true);
  glDeleteTextures(3, software_textures_);
  std::fill_n(software_textures_, 3, 0);
  software_width_ = software_height_ = 0;
  if (program_)
    glDeleteProgram(program_);
  program_ = 0;
}
bool McLinuxGpuTexture::render(AVFrame *source, GLuint output) {
  if (source && (source->colorspace == AVCOL_SPC_BT2020_NCL ||
                 source->colorspace == AVCOL_SPC_BT2020_CL))
    return false;
  if (!source || source->width <= 0 || source->height <= 0)
    return false;
  const bool hardware = source->format == AV_PIX_FMT_VAAPI;
  const bool cuda_frame = source->format == AV_PIX_FMT_CUDA;
  if (cuda_frame) {
    auto *frames = reinterpret_cast<AVHWFramesContext *>(
        source->hw_frames_ctx ? source->hw_frames_ctx->data : nullptr);
    if (!frames || frames->sw_format != AV_PIX_FMT_NV12)
      return false;
  }
  const bool planar = source->format == AV_PIX_FMT_YUV420P ||
                      source->format == AV_PIX_FMT_YUVJ420P;
  if (!hardware && !cuda_frame && !planar && source->format != AV_PIX_FMT_NV12)
    return false;
  const bool desktop = epoxy_is_desktop_gl();
  if (epoxy_gl_version() < 30 || (desktop && epoxy_gl_version() < 32 &&
                                  !epoxy_has_gl_extension("GL_ARB_sync")))
    return false;
  auto display = eglGetCurrentDisplay();
  if (hardware &&
      (display == EGL_NO_DISPLAY ||
       !epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import") ||
       !epoxy_has_egl_extension(display, "EGL_KHR_image_base") ||
       !epoxy_has_gl_extension("GL_OES_EGL_image")))
    return false;
  reap(false);
  // Only apply backpressure when four decoder surfaces are still read by GL.
  if (pending_.size() >= 4)
    reap(true);
  AVFrame *mapped = hardware ? av_frame_alloc() : nullptr;
  if (hardware && !mapped)
    return false;
  if (hardware)
    mapped->format = AV_PIX_FMT_DRM_PRIME;
  if (hardware &&
      av_hwframe_map(mapped, source,
                     AV_HWFRAME_MAP_READ | AV_HWFRAME_MAP_DIRECT) < 0) {
    av_frame_free(&mapped);
    return false;
  }
  if (cuda_frame) {
    mapped = av_frame_clone(source);
    if (!mapped)
      return false;
  }
  auto *drm = hardware
                  ? reinterpret_cast<AVDRMFrameDescriptor *>(mapped->data[0])
                  : nullptr;
  if (hardware && !drm) {
    av_frame_free(&mapped);
    return false;
  }
  struct Plane {
    int object;
    ptrdiff_t offset, pitch;
  };
  std::vector<Plane> planes;
  for (int layer = 0; drm && layer < drm->nb_layers; ++layer)
    for (int p = 0; p < drm->layers[layer].nb_planes; ++p) {
      auto plane = drm->layers[layer].planes[p];
      planes.push_back({plane.object_index, plane.offset, plane.pitch});
    }
  // NV12 only. 10-bit/P010 and unsupported layouts use the general fallback.
  bool nv12 = !hardware ||
              (drm->nb_layers == 1 &&
               drm->layers[0].format == fourcc('N', 'V', '1', '2')) ||
              (drm->nb_layers == 2 &&
               drm->layers[0].format == fourcc('R', '8', ' ', ' ') &&
               (drm->layers[1].format == fourcc('G', 'R', '8', '8') ||
                drm->layers[1].format == fourcc('R', 'G', '8', '8')));
  if (!nv12 || (hardware && planes.size() != 2)) {
    av_frame_free(&mapped);
    return false;
  }
  EGLImageKHR images[2] = {EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR};
  GLuint textures[3]{};
  void *cuda_resources[2]{}, *cuda_context = nullptr;
  bool okay = true;
  bool modifiers =
      hardware && epoxy_has_egl_extension(
                      display, "EGL_EXT_image_dma_buf_import_modifiers");
  for (int i = 0; hardware && i < 2; ++i) {
    auto plane = planes[i];
    if (plane.object < 0 || plane.object >= drm->nb_objects ||
        plane.offset < 0 || plane.pitch <= 0 ||
        plane.offset > std::numeric_limits<EGLint>::max() ||
        plane.pitch > std::numeric_limits<EGLint>::max()) {
      okay = false;
      break;
    }
    auto object = drm->objects[plane.object];
    std::vector<EGLint> attrs = {
        EGL_WIDTH,
        i ? (source->width + 1) / 2 : source->width,
        EGL_HEIGHT,
        i ? (source->height + 1) / 2 : source->height,
        EGL_LINUX_DRM_FOURCC_EXT,
        static_cast<EGLint>(i ? (drm->nb_layers == 2
                                     ? drm->layers[1].format
                                     : fourcc('G', 'R', '8', '8'))
                              : fourcc('R', '8', ' ', ' ')),
        EGL_DMA_BUF_PLANE0_FD_EXT,
        object.fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT,
        static_cast<EGLint>(plane.offset),
        EGL_DMA_BUF_PLANE0_PITCH_EXT,
        static_cast<EGLint>(plane.pitch)};
    if (modifiers && object.format_modifier != UINT64_MAX) {
      attrs.insert(attrs.end(),
                   {EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
                    static_cast<EGLint>(object.format_modifier & 0xffffffff),
                    EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
                    static_cast<EGLint>(object.format_modifier >> 32)});
    }
    attrs.push_back(EGL_NONE);
    images[i] = eglCreateImageKHR(display, EGL_NO_CONTEXT,
                                  EGL_LINUX_DMA_BUF_EXT, nullptr, attrs.data());
    if (images[i] == EGL_NO_IMAGE_KHR) {
      okay = false;
      break;
    }
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  GLint oldDrawFbo = 0, oldReadFbo = 0, oldProgram = 0, oldVao = 0,
        oldActive = 0, oldBindings[3]{}, viewport[4]{}, oldUnpackBuffer = 0,
        oldAlignment = 0, oldRowLength = 0, oldSkipRows = 0, oldSkipPixels = 0;
  GLboolean oldDiscard = glIsEnabled(GL_RASTERIZER_DISCARD);
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &oldUnpackBuffer);
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &oldAlignment);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &oldRowLength);
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, &oldSkipRows);
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &oldSkipPixels);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  GLboolean oldCull = glIsEnabled(GL_CULL_FACE),
            oldStencil = glIsEnabled(GL_STENCIL_TEST), oldColorMask[4]{};
  glGetBooleanv(GL_COLOR_WRITEMASK, oldColorMask);
  GLint oldSamplers[3]{};
  const bool samplers = !desktop || epoxy_gl_version() >= 33 ||
                        epoxy_has_gl_extension("GL_ARB_sampler_objects");
  GLboolean oldSrgb =
      epoxy_is_desktop_gl() ? glIsEnabled(GL_FRAMEBUFFER_SRGB) : GL_FALSE;
  GLboolean oldBlend = glIsEnabled(GL_BLEND),
            oldScissor = glIsEnabled(GL_SCISSOR_TEST),
            oldDepth = glIsEnabled(GL_DEPTH_TEST);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &oldDrawFbo);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &oldReadFbo);
  glGetIntegerv(GL_CURRENT_PROGRAM, &oldProgram);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &oldVao);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &oldActive);
  glGetIntegerv(GL_VIEWPORT, viewport);
  for (int i = 0; i < 3; ++i) {
    glActiveTexture(GL_TEXTURE0 + i);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &oldBindings[i]);
    if (samplers) {
      glGetIntegerv(GL_SAMPLER_BINDING, &oldSamplers[i]);
      glBindSampler(i, 0);
    }
  }
  GLuint framebuffer_ = 0, vao_ = 0;
  if (okay) {
    if (!program_)
      program_ = program();
    if (!program_)
      okay = false;
    if (okay) {
      if (!framebuffer_)
        glGenFramebuffers(1, &framebuffer_);
      if (!vao_)
        glGenVertexArrays(1, &vao_);
      glBindTexture(GL_TEXTURE_2D, output);
      if (width_ != source->width || height_ != source->height) {
        width_ = source->width;
        height_ = source->height;
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width_, height_, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, nullptr);
      }
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                             GL_TEXTURE_2D, output, 0);
      okay =
          glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
      if (okay) {
        const bool software = !hardware && !cuda_frame;
        const bool plane_storage_changed =
            software &&
            (software_width_ != source->width ||
             software_height_ != source->height || software_planar_ != planar);
        if (software) {
          if (!software_textures_[0])
            glGenTextures(3, software_textures_);
          std::copy_n(software_textures_, 3, textures);
        } else
          glGenTextures(3, textures);
        for (int i = 0; i < (planar ? 3 : 2); ++i) {
          glActiveTexture(GL_TEXTURE0 + i);
          glBindTexture(GL_TEXTURE_2D, textures[i]);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
          if (hardware)
            glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, images[i]);
          else if (cuda_frame)
            glTexImage2D(GL_TEXTURE_2D, 0, i ? GL_RG8 : GL_R8,
                         i ? (source->width + 1) / 2 : source->width,
                         i ? (source->height + 1) / 2 : source->height, 0,
                         i ? GL_RG : GL_RED, GL_UNSIGNED_BYTE, nullptr);
          else {
            int planeWidth = i ? (source->width + 1) / 2 : source->width;
            int planeHeight = i ? (source->height + 1) / 2 : source->height;
            int channels = i && !planar ? 2 : 1;
            const uint8_t *pixels = source->data[i];
            if (!pixels) {
              okay = false;
              break;
            }
            std::vector<uint8_t> packed;
            if (source->linesize[i] < planeWidth * channels ||
                source->linesize[i] % channels) {
              packed.resize(size_t(planeWidth) * planeHeight * channels);
              for (int row = 0; row < planeHeight; ++row)
                std::copy_n(pixels + ptrdiff_t(row) * source->linesize[i],
                            planeWidth * channels,
                            packed.data() +
                                size_t(row) * planeWidth * channels);
              pixels = packed.data();
              glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
            } else
              glPixelStorei(GL_UNPACK_ROW_LENGTH,
                            source->linesize[i] / channels);
            if (plane_storage_changed)
              glTexImage2D(GL_TEXTURE_2D, 0, channels == 2 ? GL_RG8 : GL_R8,
                           planeWidth, planeHeight, 0,
                           channels == 2 ? GL_RG : GL_RED, GL_UNSIGNED_BYTE,
                           nullptr);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, planeWidth, planeHeight,
                            channels == 2 ? GL_RG : GL_RED, GL_UNSIGNED_BYTE,
                            pixels);
          }
        }
        if (cuda_frame)
          okay =
              cuda().upload(source, textures, cuda_resources, &cuda_context) &&
              okay;
        if (software) {
          software_width_ = source->width;
          software_height_ = source->height;
          software_planar_ = planar;
        }
        glUseProgram(program_);
        glUniform1i(glGetUniformLocation(program_, "yPlane"), 0);
        glUniform1i(glGetUniformLocation(program_, "uvPlane"), 1);
        glUniform1i(glGetUniformLocation(program_, "vPlane"), planar ? 2 : 1);
        glUniform1i(glGetUniformLocation(program_, "planar"), planar);
        bool full = source->color_range == AVCOL_RANGE_JPEG ||
                    source->format == AV_PIX_FMT_YUVJ420P,
             bt709 = source->colorspace == AVCOL_SPC_BT709 ||
                     source->colorspace == AVCOL_SPC_UNSPECIFIED;
        float y = full ? 1.0f : 255.0f / 219.0f,
              c = full ? 1.0f : 255.0f / 224.0f;
        float matrix[9] = {y,
                           y,
                           y,
                           0,
                           c * (bt709 ? -0.187324f : -0.344136f),
                           c * (bt709 ? 1.8556f : 1.772f),
                           c * (bt709 ? 1.5748f : 1.402f),
                           c * (bt709 ? -0.468124f : -0.714136f),
                           0};
        glUniform3f(glGetUniformLocation(program_, "offset"),
                    full ? 0 : -16.0f / 255.0f, -128.0f / 255.0f,
                    -128.0f / 255.0f);
        glUniformMatrix3fv(glGetUniformLocation(program_, "matrix"), 1,
                           GL_FALSE, matrix);
        glDisable(GL_RASTERIZER_DISCARD);
        glDisable(GL_CULL_FACE);
        glDisable(GL_STENCIL_TEST);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        if (epoxy_is_desktop_gl())
          glDisable(GL_FRAMEBUFFER_SRGB);
        glDisable(GL_BLEND);
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_DEPTH_TEST);
        glViewport(0, 0, width_, height_);
        glBindVertexArray(vao_);
        if (okay)
          glDrawArrays(GL_TRIANGLES, 0, 3);
        okay = (glGetError() == GL_NO_ERROR) && okay;
        if (hardware || cuda_context) {
          GLsync fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
          if (fence) {
            Pending pending{};
            pending.fence = fence;
            pending.frame = mapped;
            mapped = nullptr;
            pending.display = display;
            pending.cuda_context = cuda_context;
            std::copy_n(cuda_resources, 2, pending.cuda_resources);
            cuda_context = nullptr;
            std::copy_n(textures, 3, pending.textures);
            std::copy_n(images, 2, pending.images);
            std::fill_n(textures, 3, 0);
            std::fill_n(images, 2, EGL_NO_IMAGE_KHR);
            pending_.push_back(pending);
            glFlush();
          } else {
            // Fence allocation failure must not release an in-use surface.
            glFinish();
            okay = false;
          }
        }
      }
    }
  }
  if (framebuffer_)
    glDeleteFramebuffers(1, &framebuffer_);
  if (vao_)
    glDeleteVertexArrays(1, &vao_);
  cuda().release(cuda_context, cuda_resources);
  if (!hardware && !cuda_frame)
    std::fill_n(textures, 3,
                0); // Software plane textures persist across frames.
  glDeleteTextures(3, textures);
  for (int i = 0; i < 2; ++i)
    if (images[i] != EGL_NO_IMAGE_KHR)
      eglDestroyImageKHR(display, images[i]);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, oldDrawFbo);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, oldReadFbo);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, oldUnpackBuffer);
  glPixelStorei(GL_UNPACK_ALIGNMENT, oldAlignment);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, oldRowLength);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, oldSkipRows);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, oldSkipPixels);
  if (oldDiscard)
    glEnable(GL_RASTERIZER_DISCARD);
  glUseProgram(oldProgram);
  glBindVertexArray(oldVao);
  glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
  if (oldCull)
    glEnable(GL_CULL_FACE);
  if (oldStencil)
    glEnable(GL_STENCIL_TEST);
  if (oldSrgb)
    glEnable(GL_FRAMEBUFFER_SRGB);
  glColorMask(oldColorMask[0], oldColorMask[1], oldColorMask[2],
              oldColorMask[3]);
  if (oldBlend)
    glEnable(GL_BLEND);
  if (oldScissor)
    glEnable(GL_SCISSOR_TEST);
  if (oldDepth)
    glEnable(GL_DEPTH_TEST);
  for (int i = 0; i < 3; ++i) {
    glActiveTexture(GL_TEXTURE0 + i);
    glBindTexture(GL_TEXTURE_2D, oldBindings[i]);
    if (samplers)
      glBindSampler(i, oldSamplers[i]);
  }
  glActiveTexture(oldActive);
  av_frame_free(&mapped);
  return okay;
}
