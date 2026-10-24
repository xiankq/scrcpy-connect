#include "include/media_codec/media_codec_plugin.h"
#include "../native/media_codec.h"
#include "audio.h"
#include "gpu_texture.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <epoxy/gl.h>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#ifndef EGL_DRM_RENDER_NODE_FILE_EXT
#define EGL_DRM_RENDER_NODE_FILE_EXT 0x3377
#endif
extern "C" {
#include <libavutil/frame.h>
}
struct _McTexture {
  FlTextureGL parent_instance;
  std::mutex *mutex;
  mc_decoder *decoder;
  GLuint name;
  mc_image image;
  McLinuxGpuTexture *gpu;
  GdkWindow *window;
  uint64_t rendered_frame;
  uint32_t width, height;
};
struct McTextureClass {
  FlTextureGLClass parent_class;
};
typedef struct _McTexture McTexture;
G_DEFINE_TYPE(McTexture, mc_texture, fl_texture_gl_get_type())
static gboolean populate(FlTextureGL *texture, uint32_t *target, uint32_t *name,
                         uint32_t *width, uint32_t *height, GError **) {
  auto *self = reinterpret_cast<McTexture *>(texture);
  std::lock_guard<std::mutex> lock(*self->mutex);
  if (!self->decoder)
    return FALSE;
  if (!self->window) {
    auto *current = gdk_gl_context_get_current();
    if (current) {
      auto *window = gdk_gl_context_get_window(current);
      if (window)
        self->window = GDK_WINDOW(g_object_ref(window));
    }
  }
  mc_status current_status{};
  mc_get_status(self->decoder, &current_status);
  if (self->rendered_frame == current_status.frame_count && self->width &&
      self->height) {
    *target = GL_TEXTURE_2D;
    *name = self->name;
    *width = self->width;
    *height = self->height;
    return TRUE;
  }
  if (!self->name)
    glGenTextures(1, &self->name);
  uint64_t sequence = 0;
  auto *frame = mc_acquire_frame_snapshot(self->decoder, &sequence);
  if (frame) {
    bool imported = self->gpu->render(frame, self->name);
    if (imported) {
      self->rendered_frame = sequence;
      self->width = frame->width;
      self->height = frame->height;
      mc_report_present(
          self->decoder, sequence,
          frame->format == AV_PIX_FMT_VAAPI
              ? "vaapi/egl"
              : (frame->format == AV_PIX_FMT_CUDA ? "cuda/gl" : "yuv/gl"),
          nullptr);
      mc_release_frame(frame);
      *target = GL_TEXTURE_2D;
      *name = self->name;
      *width = self->width;
      *height = self->height;
      return TRUE;
    }
  }
  if (!frame)
    return FALSE;
  mc_image next{};
  if (mc_copy_frame_rgba(frame, &next) != 0) {
    mc_release_frame(frame);
    mc_report_present(self->decoder, sequence, "cpu/gl",
                      "Frame conversion failed");
    return FALSE;
  }
  const bool readback = frame->hw_frames_ctx != nullptr;
  mc_release_frame(frame);
  mc_image_free(&self->image);
  self->image = next;
  if (!self->name)
    glGenTextures(1, &self->name);
  GLint previous = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous);
  glBindTexture(GL_TEXTURE_2D, self->name);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  while (glGetError() != GL_NO_ERROR) {
  }
  GLint alignment = 0, row_length = 0, unpack_buffer = 0, skip_rows = 0,
        skip_pixels = 0;
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &row_length);
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack_buffer);
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skip_rows);
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skip_pixels);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  if (self->width != self->image.width || self->height != self->image.height) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, self->image.width,
                 self->image.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    self->gpu->storage_changed();
  }
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, self->image.width, self->image.height,
                  GL_RGBA, GL_UNSIGNED_BYTE, self->image.rgba);
  const bool uploaded = glGetError() == GL_NO_ERROR;
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack_buffer);
  glPixelStorei(GL_UNPACK_ALIGNMENT, alignment);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, row_length);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, skip_rows);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, skip_pixels);
  glBindTexture(GL_TEXTURE_2D, previous);
  mc_report_present(self->decoder, sequence,
                    readback ? "readback/gl" : "cpu/gl",
                    uploaded ? nullptr : "GL texture upload failed");
  if (!uploaded)
    return FALSE;
  self->rendered_frame = sequence;
  self->width = self->image.width;
  self->height = self->image.height;
  *target = GL_TEXTURE_2D;
  *name = self->name;
  *width = self->image.width;
  *height = self->image.height;
  return TRUE;
}
static void texture_finalize(GObject *object) {
  auto *self = reinterpret_cast<McTexture *>(object);
  // 同一显示设备上的 GDK context 共享纹理与程序。
  // 注销后在平台线程使用独立 context，避免跨线程移动 Flutter 光栅 context 或逐会话泄漏 GL 纹理。
  // context 私有的 FBO/VAO 在 populate 期间删除。
  if (self->window && !gdk_window_is_destroyed(self->window)) {
    GdkGLContext *previous = gdk_gl_context_get_current();
    if (previous)
      g_object_ref(previous);
    g_autoptr(GError) error = nullptr;
    g_autoptr(GdkGLContext) cleanup =
        gdk_window_create_gl_context(self->window, &error);
    if (cleanup && gdk_gl_context_realize(cleanup, &error)) {
      gdk_gl_context_make_current(cleanup);
      if (self->name)
        glDeleteTextures(1, &self->name);
      self->gpu->release_shared_resources();
      glFlush();
    }
    if (previous) {
      gdk_gl_context_make_current(previous);
      g_object_unref(previous);
    } else
      gdk_gl_context_clear_current();
  }
  if (self->window)
    g_object_unref(self->window);
  mc_image_free(&self->image);
  delete self->gpu;
  delete self->mutex;
  G_OBJECT_CLASS(mc_texture_parent_class)->finalize(object);
}
static void mc_texture_class_init(McTextureClass *klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = populate;
  G_OBJECT_CLASS(klass)->finalize = texture_finalize;
}
static void mc_texture_init(McTexture *self) {
  self->mutex = new std::mutex;
  self->decoder = nullptr;
  self->name = 0;
  self->image = {};
  self->gpu = new McLinuxGpuTexture;
  self->window = nullptr;
  self->rendered_frame = 0;
  self->width = 0;
  self->height = 0;
}
namespace {
// 运行时加载 ALSA，使无音频设备的系统仍可使用插件；非阻塞写入和有界等待保证释放有界。
using Audio = mc_linux::Audio;
struct Output {
  FlTextureRegistrar *registrar = nullptr;
  McTexture *texture = nullptr;
  mc_decoder *decoder = nullptr;
  std::unique_ptr<Audio> audio;
  ~Output() {
    if (texture) {
      std::lock_guard<std::mutex> lock(*texture->mutex);
      texture->decoder = nullptr;
    }
    mc_destroy(decoder);
    if (texture) {
      fl_texture_registrar_unregister_texture(registrar, FL_TEXTURE(texture));
      g_object_unref(texture);
    }
  }
};
struct Plugin {
  FlTextureRegistrar *registrar;
  FlView *view;
  std::unordered_map<int64_t, std::unique_ptr<Output>> outputs;
  int64_t next = 1;
};
std::string render_node(FlView *view) {
  auto *window = gtk_widget_get_window(GTK_WIDGET(view));
  if (!window)
    return "";
  auto *previous = gdk_gl_context_get_current();
  if (previous)
    g_object_ref(previous);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context =
      gdk_window_create_gl_context(window, &error);
  std::string result;
  if (context && gdk_gl_context_realize(context, &error)) {
    gdk_gl_context_make_current(context);
    auto display = eglGetCurrentDisplay();
    if (display != EGL_NO_DISPLAY &&
        epoxy_has_egl_extension(display, "EGL_EXT_device_query")) {
      EGLAttrib device = 0;
      if (eglQueryDisplayAttribEXT(display, EGL_DEVICE_EXT, &device)) {
        auto egl_device = reinterpret_cast<EGLDeviceEXT>(device);
        const char *extensions =
            eglQueryDeviceStringEXT(egl_device, EGL_EXTENSIONS);
        if (extensions &&
            strstr(extensions, "EGL_EXT_device_drm_render_node")) {
          auto *node =
              eglQueryDeviceStringEXT(egl_device, EGL_DRM_RENDER_NODE_FILE_EXT);
          if (node)
            result = node;
        }
      }
    }
  }
  if (previous) {
    gdk_gl_context_make_current(previous);
    g_object_unref(previous);
  } else
    gdk_gl_context_clear_current();
  return result;
}
FlValue *get(FlValue *args, const char *key) {
  return args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, key)
             : nullptr;
}
int64_t integer(FlValue *args, const char *key, int64_t fallback = 0) {
  auto *v = get(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v)
                                                        : fallback;
}
std::string string(FlValue *args, const char *key) {
  auto *v = get(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : "";
}
uint32_t codec_number(const std::string &codec) {
  if (codec == "h264")
    return 1;
  if (codec == "h265" || codec == "hevc")
    return 2;
  if (codec == "av1")
    return 3;
  if (codec == "vp8")
    return 4;
  if (codec == "vp9")
    return 5;
  if (codec == "pcm_s16le" || codec == "raw")
    return 100;
  return 0;
}
void put(FlValue *map, const char *key, FlValue *value) {
  fl_value_set_string_take(map, key, value);
}
void ready(void *user) {
  auto *output = static_cast<Output *>(user);
  if (output->texture)
    fl_texture_registrar_mark_texture_frame_available(
        output->registrar, FL_TEXTURE(output->texture));
}
int64_t pcm(void *user, const uint8_t *data, size_t len) {
  auto *output = static_cast<Output *>(user);
  return output->audio ? output->audio->write(data, len) : -1;
}
void respond(FlMethodCall *call, FlValue *value) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}
void error(FlMethodCall *call, const char *code, const char *message) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
  fl_method_call_respond(call, response, nullptr);
}
void method(FlMethodChannel *, FlMethodCall *call, gpointer user) {
  auto *plugin = static_cast<Plugin *>(user);
  const char *name = fl_method_call_get_name(call);
  auto *args = fl_method_call_get_args(call);
  if (strcmp(name, "createVideo") == 0 || strcmp(name, "createAudio") == 0) {
    bool audio = strcmp(name, "createAudio") == 0;
    auto output = std::make_unique<Output>();
    output->registrar = plugin->registrar;
    if (audio) {
      output->audio = std::make_unique<Audio>();
      if (!output->audio->ready()) {
        error(call, "audio_unavailable",
              "Unable to open the system audio output");
        return;
      }
    } else {
      output->texture = reinterpret_cast<McTexture *>(
          g_object_new(mc_texture_get_type(), nullptr));
      if (!fl_texture_registrar_register_texture(plugin->registrar,
                                                 FL_TEXTURE(output->texture))) {
        error(call, "texture_unavailable", "Unable to register texture");
        return;
      }
    }
    mc_config config{};
    config.struct_size = sizeof(config);
    config.codec = audio ? 100 : codec_number(string(args, "codec"));
    config.width = integer(args, "width");
    config.height = integer(args, "height");
    config.generation = integer(args, "generation");
    // EGL 公开渲染节点时，VAAPI 必须在 Flutter 渲染 GPU 上解码；旧 EGL/GLX 保留默认设备及有界 CPU 回退。
    std::string hardware_device = audio ? "" : render_node(plugin->view);
    if (!hardware_device.empty())
      hardware_device = "vaapi:" + hardware_device;
    config.hardware_device =
        hardware_device.empty() ? nullptr : hardware_device.c_str();
    config.user = output.get();
    config.frame_ready = ready;
    config.pcm = pcm;
    config.audio_pause = [](void *user, int32_t paused) {
      auto *o = static_cast<Output *>(user);
      if (o->audio)
        o->audio->pause(paused != 0);
    };
    config.audio_state = [](void *user, mc_audio_state *state) -> int32_t {
      auto *o = static_cast<Output *>(user);
      return o->audio ? o->audio->state(state) : -1;
    };
    config.audio_close = [](void *user) {
      auto *o = static_cast<Output *>(user);
      if (o->audio)
        o->audio->shutdown();
    };
    output->decoder = mc_create(&config);
    if (output->texture)
      output->texture->decoder = output->decoder;
    auto source = string(args, "sourceId");
    if (!output->decoder || mc_attach(output->decoder, source.c_str(),
                                      integer(args, "attachAddress"),
                                      integer(args, "detachAddress")) != 0) {
      error(call, "attach_failed", "Unable to attach the remote media source");
      return;
    }
    int64_t handle = plugin->next++;
    g_autoptr(FlValue) result = fl_value_new_map();
    put(result, "handle", fl_value_new_int(handle));
    put(result, "decoderAddress",
        fl_value_new_int(reinterpret_cast<intptr_t>(output->decoder)));
    FlValue *api = fl_value_new_map();
    put(api, "getStatusAddress",
        fl_value_new_int(reinterpret_cast<intptr_t>(&mc_get_status)));
    put(api, "setPausedAddress",
        fl_value_new_int(reinterpret_cast<intptr_t>(&mc_set_paused)));
    put(api, "setVolumeAddress",
        fl_value_new_int(reinterpret_cast<intptr_t>(&mc_set_volume)));
    put(result, "nativeApi", api);
    put(result, "textureId",
        fl_value_new_int(output->texture
                             ? fl_texture_get_id(FL_TEXTURE(output->texture))
                             : -1));
    put(result, "width", fl_value_new_int(config.width));
    put(result, "height", fl_value_new_int(config.height));
    plugin->outputs.emplace(handle, std::move(output));
    respond(call, result);
    return;
  }
  auto found = plugin->outputs.find(integer(args, "handle"));
  if (found == plugin->outputs.end()) {
    if (strcmp(name, "dispose") == 0) {
      respond(call, nullptr);
      return;
    }
    error(call, "unknown_handle", "Media output no longer exists");
    return;
  }
  auto *output = found->second.get();
  if (strcmp(name, "dispose") == 0) {
    plugin->outputs.erase(found);
    respond(call, nullptr);
    return;
  }
  if (strcmp(name, "snapshot") == 0) {
    mc_image image{};
    if (mc_copy_rgba_scaled(output->decoder, integer(args, "width"),
                            integer(args, "height"), &image) != 0) {
      respond(call, nullptr);
      return;
    }
    g_autoptr(FlValue) result = fl_value_new_map();
    put(result, "width", fl_value_new_int(image.width));
    put(result, "height", fl_value_new_int(image.height));
    put(result, "rgba", fl_value_new_uint8_list(image.rgba, image.size));
    mc_image_free(&image);
    respond(call, result);
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(call, response, nullptr);
}
} // namespace
void media_codec_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  auto *plugin =
      new Plugin{fl_plugin_registrar_get_texture_registrar(registrar),
                 fl_plugin_registrar_get_view(registrar),
                 {},
                 1};
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "media_codec", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method, plugin,
      [](gpointer p) { delete static_cast<Plugin *>(p); });
}
