#include <jni.h>
#include <android/native_window_jni.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <memory>
#include "media_codec.h"

namespace {
JavaVM* vm = nullptr;
struct Output {
  mc_decoder* decoder = nullptr;
  ANativeWindow* window = nullptr;
  jobject listener = nullptr;
  jmethodID frame = nullptr;
  jmethodID pcm = nullptr;
  std::atomic<uint32_t> width{0};
  std::atomic<uint32_t> height{0};
};
struct Environment {
  JNIEnv* env = nullptr;
  bool attached = false;
  Environment() {
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
      attached = vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
    }
  }
  ~Environment() { if (attached) vm->DetachCurrentThread(); }
};
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
void boolean(JNIEnv* env, jobject target, const char* key, bool value) {
  jclass cls = env->FindClass("java/lang/Boolean");
  jobject number = env->CallStaticObjectMethod(cls, env->GetStaticMethodID(cls, "valueOf", "(Z)Ljava/lang/Boolean;"), static_cast<jboolean>(value));
  env->DeleteLocalRef(cls); put(env, target, key, number);
}
void frame_ready(void* context) {
  auto* output = static_cast<Output*>(context);
  mc_status status{}; mc_get_status(output->decoder, &status);
  // Hardware MediaCodec releases its buffers directly to this Surface. Only
  // the fallback software path converts pixels and locks the native window.
  if (!status.hardware_accelerated && output->window) {
    mc_image image{};
    if (mc_copy_rgba(output->decoder, &image)) {
      ANativeWindow_setBuffersGeometry(output->window, image.width, image.height, WINDOW_FORMAT_RGBA_8888);
      ANativeWindow_Buffer buffer{};
      if (ANativeWindow_lock(output->window, &buffer, nullptr) == 0) {
        const auto rows = std::min<uint32_t>(image.height, buffer.height);
        const auto bytes = std::min<uint32_t>(image.width, buffer.width) * 4;
        for (uint32_t y = 0; y < rows; ++y)
          memcpy(static_cast<uint8_t*>(buffer.bits) + y * buffer.stride * 4,
                 image.rgba + y * image.stride, bytes);
        ANativeWindow_unlockAndPost(output->window);
      }
      mc_image_free(&image);
    }
  }
  if (output->width != status.width || output->height != status.height) {
    output->width = status.width; output->height = status.height;
    Environment env;
    if (env.env) {
      env.env->CallVoidMethod(output->listener, output->frame,
                             static_cast<jint>(status.width), static_cast<jint>(status.height));
      if (env.env->ExceptionCheck()) env.env->ExceptionClear();
    }
  }
}
int64_t pcm_ready(void* context, const uint8_t* bytes, size_t length) {
  auto* output = static_cast<Output*>(context);
  Environment env;
  if (!env.env || length > INT32_MAX) return -1;
  jbyteArray array = env.env->NewByteArray(static_cast<jsize>(length));
  if (!array) return -1;
  env.env->SetByteArrayRegion(array, 0, static_cast<jsize>(length), reinterpret_cast<const jbyte*>(bytes));
  jlong accepted = env.env->CallLongMethod(output->listener, output->pcm, array);
  if (env.env->ExceptionCheck()) { env.env->ExceptionClear(); accepted = -1; }
  env.env->DeleteLocalRef(array);
  return accepted;
}
Output* output(jlong handle) { return reinterpret_cast<Output*>(static_cast<uintptr_t>(handle)); }
}

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* value, void*) {
  vm = value; return JNI_VERSION_1_6;
}
#define JNI_METHOD(name) Java_dev_scrcpyconnect_media_1codec_MediaCodecPlugin_##name
extern "C" JNIEXPORT jlong JNICALL JNI_METHOD(nativeCreate)(JNIEnv* env, jclass,
    jobject listener, jobject surface, jint codec, jint width, jint height,
    jlong generation, jstring source, jlong attach, jlong detach) {
  auto value = std::make_unique<Output>();
  value->listener = env->NewGlobalRef(listener);
  jclass cls = env->GetObjectClass(listener);
  value->frame = env->GetMethodID(cls, "onFrame", "(II)V");
  value->pcm = env->GetMethodID(cls, "onPcm", "([B)J");
  env->DeleteLocalRef(cls);
  value->width = width; value->height = height;
  value->window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
  mc_config config{}; config.struct_size = sizeof(config); config.codec = codec;
  config.width = width; config.height = height; config.generation = generation;
  config.user = value.get(); config.frame_ready = frame_ready; config.pcm = pcm_ready;
  config.native_window = value->window;
  value->decoder = mc_create(&config);
  bool attached = false;
  if (value->decoder && source && attach && detach) {
    const char* id = env->GetStringUTFChars(source, nullptr);
    attached = mc_attach(value->decoder, id, static_cast<uintptr_t>(attach), static_cast<uintptr_t>(detach)) == 0;
    env->ReleaseStringUTFChars(source, id);
  }
  if (!attached) {
    if (value->decoder) mc_destroy(value->decoder);
    if (value->window) ANativeWindow_release(value->window);
    env->DeleteGlobalRef(value->listener); return 0;
  }
  return static_cast<jlong>(reinterpret_cast<uintptr_t>(value.release()));
}
extern "C" JNIEXPORT jobject JNICALL JNI_METHOD(nativeStatus)(JNIEnv* env, jclass, jlong handle) {
  mc_status status{}; if (handle) mc_get_status(output(handle)->decoder, &status);
  jobject value = map(env);
  integer(env, value, "width", status.width); integer(env, value, "height", status.height);
  integer(env, value, "frameCount", status.frame_count); integer(env, value, "bytesWritten", status.bytes_written);
  integer(env, value, "positionMs", status.position_us / 1000);
  integer(env, value, "errorCode", status.error_code);
  boolean(env, value, "hardwareAccelerated", status.hardware_accelerated);
  boolean(env, value, "nativeReady", status.native_ready);
  boolean(env, value, "firstFrame", status.frame_count > 0);
  boolean(env, value, "ended", status.ended);
  put(env, value, "decoderName", env->NewStringUTF(status.decoder_name));
  put(env, value, "error", env->NewStringUTF(status.error)); return value;
}
extern "C" JNIEXPORT jobject JNICALL JNI_METHOD(nativeSnapshot)(JNIEnv* env, jclass, jlong handle, jint max_width, jint max_height) {
  mc_image image{};
  if (!handle || !mc_copy_rgba_scaled(output(handle)->decoder, max_width, max_height, &image)) return nullptr;
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
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeSetVolume)(JNIEnv*, jclass, jlong handle, jdouble volume) {
  if (handle) mc_set_volume(output(handle)->decoder, volume);
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeDispose)(JNIEnv* env, jclass, jlong handle) {
  if (!handle) return;
  std::unique_ptr<Output> value(output(handle));
  mc_destroy(value->decoder);
  if (value->window) ANativeWindow_release(value->window);
  env->DeleteGlobalRef(value->listener);
}
