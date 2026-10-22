#ifndef FLUTTER_PLUGIN_MEDIA_CODEC_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_MEDIA_CODEC_PLUGIN_C_API_H_
#include <flutter_plugin_registrar.h>
#ifdef FLUTTER_PLUGIN_IMPL
#define MEDIA_CODEC_PLUGIN_EXPORT __declspec(dllexport)
#else
#define MEDIA_CODEC_PLUGIN_EXPORT __declspec(dllimport)
#endif
#ifdef __cplusplus
extern "C" {
#endif
MEDIA_CODEC_PLUGIN_EXPORT void MediaCodecPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);
#ifdef __cplusplus
}
#endif
#endif
