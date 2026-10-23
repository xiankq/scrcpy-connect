#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <condition_variable>
#include <thread>
#include "media_codec.h"
extern "C" {
#include <libavcodec/jni.h>
#include <libavutil/frame.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
}

namespace {
JavaVM* vm = nullptr;
struct Output;
void render_software(Output*);
struct Output {
  mc_decoder* decoder = nullptr;
  ANativeWindow* window = nullptr;
  std::mutex window_mutex;
  jobject listener = nullptr;
  jmethodID frame = nullptr;
  jmethodID pcm = nullptr;
  jmethodID pause = nullptr;
  jmethodID audio_close = nullptr;
  jmethodID audio_state = nullptr;
  jmethodID hardware_kind = nullptr;
  std::atomic<uint32_t> width{0};
  std::atomic<uint32_t> height{0};
  std::atomic<bool> closing{false};
  std::mutex render_mutex;
  std::condition_variable render_wake;
  std::thread render_thread;
  bool render_pending = false;
  SwsContext* scaler = nullptr;
  void schedule_render() {
    std::lock_guard<std::mutex> guard(render_mutex);
    if (closing) return;
    if (!render_thread.joinable()) render_thread = std::thread([this] {
      std::unique_lock<std::mutex> lock(render_mutex);
      for (;;) {
        render_wake.wait(lock, [this] { return closing || render_pending; });
        if (closing) return;
        render_pending = false;
        lock.unlock(); render_software(this); lock.lock();
      }
    });
    render_pending = true; render_wake.notify_one();
  }
  void stop_render() {
    { std::lock_guard<std::mutex> guard(render_mutex); closing = true; }
    render_wake.notify_all();
    if (render_thread.joinable()) render_thread.join();
  }
  ~Output() { stop_render(); sws_freeContext(scaler); }
};
// Attach each native worker once, and detach only when that thread exits.
struct ThreadEnvironment {
  JNIEnv* env = nullptr;
  bool attached = false;
  ThreadEnvironment() {
    if (vm && vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK)
      attached = vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
  }
  ~ThreadEnvironment() { if (attached) vm->DetachCurrentThread(); }
};
struct Environment {
  JNIEnv* env;
  Environment() { thread_local ThreadEnvironment thread; env = thread.env; }
};
bool callback_failed(JNIEnv* env, Output* output, const char* action) {
  if (!env->ExceptionCheck()) return false;
  env->ExceptionDescribe(); env->ExceptionClear();
  __android_log_print(ANDROID_LOG_ERROR, "media_codec", "%s callback failed", action);
  if (output->decoder) mc_report_present(output->decoder, 0, "android-jni", action);
  return true;
}
jobject map(JNIEnv* env) {
  jclass cls = env->FindClass("java/util/HashMap");
  jobject value = env->NewObject(cls, env->GetMethodID(cls, "<init>", "()V"));
  env->DeleteLocalRef(cls); return value;
}
void put(JNIEnv* env, jobject target, const char* key, jobject value) {
  jclass cls = env->GetObjectClass(target);
  jstring name = env->NewStringUTF(key);
  jobject previous = env->CallObjectMethod(target,
      env->GetMethodID(cls, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"), name, value);
  if (previous) env->DeleteLocalRef(previous);
  env->DeleteLocalRef(name); env->DeleteLocalRef(cls); env->DeleteLocalRef(value);
}
void integer(JNIEnv* env, jobject target, const char* key, int64_t value) {
  jclass cls = env->FindClass("java/lang/Long");
  jobject number = env->CallStaticObjectMethod(cls, env->GetStaticMethodID(cls, "valueOf", "(J)Ljava/lang/Long;"), static_cast<jlong>(value));
  env->DeleteLocalRef(cls); put(env, target, key, number);
}
void render_software(Output* output) {
  uint64_t sequence = 0;
  AVFrame* frame = mc_acquire_frame_snapshot(output->decoder, &sequence);
  if (!frame) return;
  const AVPixFmtDescriptor* format = av_pix_fmt_desc_get(static_cast<AVPixelFormat>(frame->format));
  if (format && (format->flags & AV_PIX_FMT_FLAG_HWACCEL)) { mc_release_frame(frame); return; }
  ANativeWindow* window = nullptr;
  {
    std::lock_guard<std::mutex> guard(output->window_mutex);
    window = output->window;
    if (window) ANativeWindow_acquire(window);
  }
  // A dequeue may block until the consumer releases a buffer. Never hold the
  // swap mutex while waiting: cleanup must be able to withdraw the target and
  // abandon its consumer, waking the platform dequeue.
  const char* error = nullptr;
  if (window) {
    output->scaler = sws_getCachedContext(output->scaler, frame->width, frame->height,
        static_cast<AVPixelFormat>(frame->format), frame->width, frame->height,
        AV_PIX_FMT_RGBA, SWS_BILINEAR, nullptr, nullptr, nullptr);
    int space = frame->colorspace == AVCOL_SPC_SMPTE170M || frame->colorspace == AVCOL_SPC_BT470BG ? SWS_CS_ITU601 :
        frame->colorspace == AVCOL_SPC_SMPTE240M ? SWS_CS_SMPTE240M : frame->colorspace == AVCOL_SPC_FCC ? SWS_CS_FCC :
        frame->colorspace == AVCOL_SPC_BT2020_NCL || frame->colorspace == AVCOL_SPC_BT2020_CL ? SWS_CS_BT2020 : SWS_CS_ITU709;
    const int* coefficients = sws_getCoefficients(space);
    if (!output->scaler || sws_setColorspaceDetails(output->scaler, coefficients,
        frame->color_range == AVCOL_RANGE_JPEG, coefficients, 1, 0, 1 << 16, 1 << 16) < 0)
      error = "Software frame conversion setup failed";
    else if (ANativeWindow_setBuffersGeometry(window, frame->width, frame->height, WINDOW_FORMAT_RGBA_8888) != 0)
      error = "Native window geometry update failed";
    else {
      ANativeWindow_Buffer buffer{};
      if (ANativeWindow_lock(window, &buffer, nullptr) != 0) error = "Native window lock failed";
      else {
        if (buffer.width < frame->width || buffer.height < frame->height) error = "Native window buffer is smaller than decoded frame";
        else {
          uint8_t* planes[4] = {static_cast<uint8_t*>(buffer.bits), nullptr, nullptr, nullptr};
          int strides[4] = {buffer.stride * 4, 0, 0, 0};
          // Convert straight into the dequeued buffer: no per-frame RGBA
          // allocation or second full-frame CPU memcpy.
          if (sws_scale(output->scaler, frame->data, frame->linesize, 0, frame->height, planes, strides) != frame->height)
            error = "Software frame conversion failed";
        }
        if (ANativeWindow_unlockAndPost(window) != 0) error = "Native window post failed";
      }
    }
  } else error = "Android surface unavailable";
  bool current = false;
  {
    std::lock_guard<std::mutex> guard(output->window_mutex);
    current = output->window == window && !output->closing;
  }
  if (window) ANativeWindow_release(window);
  mc_release_frame(frame);
  if (current) mc_report_present(output->decoder, sequence, "android-software-window", error);
}
void frame_ready(void* context) {
  auto* output = static_cast<Output*>(context);
  if (output->closing) return;
  mc_status status{}; mc_get_status(output->decoder, &status);
  // A software component (e.g. c2.android.avc.decoder) still renders through
  // MediaCodec's opaque Surface API; physical acceleration is diagnostic only.
  if (strstr(status.decoder_name, "_mediacodec")) {
    std::lock_guard<std::mutex> guard(output->window_mutex);
    mc_report_present(output->decoder, 0, "android-mediacodec-surface",
        output->window ? nullptr : "Android surface unavailable");
  } else output->schedule_render();
  if (output->width != status.width || output->height != status.height) {
    output->width = status.width; output->height = status.height;
    Environment env;
    if (env.env) {
      env.env->CallVoidMethod(output->listener, output->frame,
                             static_cast<jint>(status.width), static_cast<jint>(status.height));
      callback_failed(env.env, output, "Frame size notification failed");
    }
  }
}
int64_t pcm_ready(void* context, const uint8_t* bytes, size_t length) {
  auto* output = static_cast<Output*>(context);
  Environment env;
  if (!env.env || length > INT32_MAX) return -1;
  jobject buffer = env.env->NewDirectByteBuffer(const_cast<uint8_t*>(bytes), static_cast<jlong>(length));
  if (!buffer) { callback_failed(env.env, output, "PCM buffer allocation failed"); return -1; }
  jlong accepted = env.env->CallLongMethod(output->listener, output->pcm, buffer);
  if (callback_failed(env.env, output, "PCM write failed")) accepted = -1;
  env.env->DeleteLocalRef(buffer);
  return accepted;
}
void audio_close(void* context) {
  auto* output = static_cast<Output*>(context); Environment env;
  if (!env.env) return;
  env.env->CallVoidMethod(output->listener, output->audio_close);
  callback_failed(env.env, output, "PCM close failed");
}
void audio_pause(void* context, int32_t paused) {
  auto* output = static_cast<Output*>(context); Environment env;
  if (!env.env) return;
  env.env->CallVoidMethod(output->listener, output->pause, static_cast<jboolean>(paused));
  callback_failed(env.env, output, "PCM pause failed");
}
int32_t hardware_kind(void* context, const char* name) {
  auto* output = static_cast<Output*>(context); Environment env;
  if (!env.env || !name) return -1;
  jstring component = env.env->NewStringUTF(name);
  if (!component) { callback_failed(env.env, output, "Codec name allocation failed"); return -1; }
  jint kind = env.env->CallIntMethod(output->listener, output->hardware_kind, component);
  bool failed = callback_failed(env.env, output, "Codec hardware query failed");
  env.env->DeleteLocalRef(component);
  return failed ? -1 : kind;
}
int32_t audio_state(void* context, mc_audio_state* state) {
  auto* output = static_cast<Output*>(context); Environment env;
  if (!env.env) return -1;
  jobject buffer = env.env->NewDirectByteBuffer(state, sizeof(*state));
  if (!buffer) { callback_failed(env.env, output, "Audio clock buffer allocation failed"); return -1; }
  env.env->CallVoidMethod(output->listener, output->audio_state, buffer);
  bool failed = callback_failed(env.env, output, "Audio clock query failed");
  env.env->DeleteLocalRef(buffer);
  return failed ? -1 : 0;
}
Output* output(jlong handle) { return reinterpret_cast<Output*>(static_cast<uintptr_t>(handle)); }
}

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* value, void*) {
  vm = value;
  // NDK decode still uses FFmpeg's Java codec-list/profile discovery when a
  // JVM is available. Register it before any decoder can be constructed.
  return av_jni_set_java_vm(value, nullptr) < 0 ? JNI_ERR : JNI_VERSION_1_6;
}
#define JNI_METHOD(name) Java_dev_scrcpyconnect_media_1codec_MediaCodecPlugin_##name
extern "C" JNIEXPORT jlong JNICALL JNI_METHOD(nativeCreate)(JNIEnv* env, jclass,
    jobject listener, jobject surface, jint codec, jint width, jint height,
    jlong generation, jstring source, jlong attach, jlong detach) {
  auto value = std::make_unique<Output>();
  if (!listener) return 0;
  value->listener = env->NewGlobalRef(listener);
  if (!value->listener) return 0;
  jclass cls = env->GetObjectClass(listener);
  auto fail = [&]() -> jlong {
    if (cls) env->DeleteLocalRef(cls);
    env->DeleteGlobalRef(value->listener);
    // Do not execute another lookup with NoSuchMethodError pending: ART aborts.
    if (env->ExceptionCheck()) env->ExceptionClear();
    jclass exception = env->FindClass("java/lang/IllegalStateException");
    if (exception) {
      env->ThrowNew(exception, "Native media callback signature is unavailable; check consumer keep rules");
      env->DeleteLocalRef(exception);
    }
    return 0;
  };
  if (!cls) return fail();
  value->frame = env->GetMethodID(cls, "onFrame", "(II)V");
  if (!value->frame || env->ExceptionCheck()) return fail();
  value->pcm = env->GetMethodID(cls, "onPcm", "(Ljava/nio/ByteBuffer;)J");
  if (!value->pcm || env->ExceptionCheck()) return fail();
  value->pause = env->GetMethodID(cls, "onPaused", "(Z)V");
  if (!value->pause || env->ExceptionCheck()) return fail();
  value->audio_state = env->GetMethodID(cls, "onAudioState", "(Ljava/nio/ByteBuffer;)V");
  if (!value->audio_state || env->ExceptionCheck()) return fail();
  value->hardware_kind = env->GetMethodID(cls, "onHardwareDecoder", "(Ljava/lang/String;)I");
  if (!value->hardware_kind || env->ExceptionCheck()) return fail();
  value->audio_close = env->GetMethodID(cls, "onAudioClosed", "()V");
  if (!value->audio_close || env->ExceptionCheck()) return fail();
  env->DeleteLocalRef(cls); cls = nullptr;
  value->width = width; value->height = height;
  value->window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
  mc_config config{}; config.struct_size = sizeof(config); config.codec = codec;
  config.width = width; config.height = height; config.generation = generation;
  config.user = value.get(); config.frame_ready = frame_ready; config.pcm = pcm_ready;
  config.native_window = value->window;
  config.audio_pause = audio_pause; config.audio_state = audio_state;
  config.hardware_kind = hardware_kind; config.audio_close = audio_close;
  value->decoder = mc_create(&config);
  bool attached = false;
  if (value->decoder && source && attach && detach) {
    const char* id = env->GetStringUTFChars(source, nullptr);
    if (id) {
      attached = mc_attach(value->decoder, id, static_cast<uintptr_t>(attach), static_cast<uintptr_t>(detach)) == 0;
      env->ReleaseStringUTFChars(source, id);
    }
  }
  if (!attached) {
    value->stop_render();
    if (value->decoder) mc_destroy(value->decoder);
    if (value->window) ANativeWindow_release(value->window);
    env->DeleteGlobalRef(value->listener); return 0;
  }
  return static_cast<jlong>(reinterpret_cast<uintptr_t>(value.release()));
}
extern "C" JNIEXPORT jobject JNICALL JNI_METHOD(nativeBindings)(JNIEnv* env, jclass, jlong handle) {
  if (!handle) return nullptr;
  jobject value = map(env), api = map(env);
  integer(env, value, "decoderAddress", reinterpret_cast<uintptr_t>(output(handle)->decoder));
  integer(env, api, "getStatusAddress", reinterpret_cast<uintptr_t>(&mc_get_status));
  integer(env, api, "setPausedAddress", reinterpret_cast<uintptr_t>(&mc_set_paused));
  integer(env, api, "setVolumeAddress", reinterpret_cast<uintptr_t>(&mc_set_volume));
  put(env, value, "nativeApi", api); return value;
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeSetSurface)(JNIEnv* env, jclass, jlong handle, jobject surface) {
  if (!handle) return;
  auto* value = output(handle);
  ANativeWindow* next = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
  ANativeWindow* previous = nullptr;
  {
    std::lock_guard<std::mutex> lock(value->window_mutex);
    if (next == value->window) {
      if (next) ANativeWindow_release(next);
      return;
    }
    // A renderer holds its own native reference. Publish the new target before
    // the synchronous core swap, which may immediately publish a replay.
    previous = value->window;
    value->window = next;
  }
  mc_set_native_window(value->decoder, next);
  if (previous) ANativeWindow_release(previous);
}
extern "C" JNIEXPORT jobject JNICALL JNI_METHOD(nativeSnapshot)(JNIEnv* env, jclass, jlong handle, jint max_width, jint max_height) {
  mc_image image{};
  if (!handle || mc_copy_rgba_scaled(output(handle)->decoder, max_width, max_height, &image) != 0) return nullptr;
  const size_t packed = image.width * 4u;
  if (packed * image.height > INT32_MAX) { mc_image_free(&image); return nullptr; }
  jbyteArray bytes = env->NewByteArray(static_cast<jsize>(packed * image.height));
  if (!bytes) { mc_image_free(&image); return nullptr; }
  for (uint32_t y = 0; y < image.height; ++y)
    env->SetByteArrayRegion(bytes, static_cast<jsize>(y * packed), static_cast<jsize>(packed),
                           reinterpret_cast<jbyte*>(image.rgba + y * image.stride));
  jobject value = map(env); integer(env, value, "width", image.width); integer(env, value, "height", image.height);
  put(env, value, "rgba", bytes); mc_image_free(&image); return value;
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeSetPaused)(JNIEnv*, jclass, jlong handle, jboolean paused) {
  if (handle) mc_set_paused(output(handle)->decoder, paused);
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeDispose)(JNIEnv* env, jclass, jlong handle) {
  if (!handle) return;
  std::unique_ptr<Output> value(output(handle));
  value->stop_render();
  mc_destroy(value->decoder);
  if (value->window) ANativeWindow_release(value->window);
  env->DeleteGlobalRef(value->listener);
}
