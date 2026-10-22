#include "include/media_codec/media_codec_plugin.h"
#include "../native/media_codec.h"
#include "gpu_texture.h"
#include <epoxy/gl.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
struct _McTexture { FlTextureGL parent_instance; std::mutex* mutex; mc_decoder* decoder; GLuint name; mc_image image; McLinuxGpuTexture* gpu; };
struct McTextureClass { FlTextureGLClass parent_class; };
typedef struct _McTexture McTexture;
G_DEFINE_TYPE(McTexture,mc_texture,fl_texture_gl_get_type())
static gboolean populate(FlTextureGL* texture,uint32_t* target,uint32_t* name,uint32_t* width,uint32_t* height,GError**) {
  auto* self=reinterpret_cast<McTexture*>(texture);
  std::lock_guard<std::mutex> lock(*self->mutex);
  if(!self->decoder)return FALSE;
  if(!self->name)glGenTextures(1,&self->name);
  auto* frame=mc_acquire_frame(self->decoder);
  if(frame) {
    bool imported=self->gpu->render(frame,self->name);
    mc_release_frame(frame);
    if(imported){mc_status status{};mc_get_status(self->decoder,&status);*target=GL_TEXTURE_2D;*name=self->name;*width=status.width;*height=status.height;return TRUE;}
  }
  mc_image next{};
  if(mc_copy_rgba(self->decoder,&next)==0) {mc_image_free(&self->image);self->image=next;}
  if(!self->image.rgba)return FALSE;
  if(!self->name)glGenTextures(1,&self->name);
  GLint previous=0;glGetIntegerv(GL_TEXTURE_BINDING_2D,&previous);
  glBindTexture(GL_TEXTURE_2D,self->name);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,self->image.width,self->image.height,0,GL_RGBA,GL_UNSIGNED_BYTE,self->image.rgba);
  glBindTexture(GL_TEXTURE_2D,previous);
  *target=GL_TEXTURE_2D;*name=self->name;*width=self->image.width;*height=self->image.height;return TRUE;
}
static void texture_finalize(GObject* object) {
  auto* self=reinterpret_cast<McTexture*>(object);
  // Texture objects belong to Flutter GL context. Its teardown releases GL names.
  mc_image_free(&self->image);delete self->gpu;delete self->mutex;
  G_OBJECT_CLASS(mc_texture_parent_class)->finalize(object);
}
static void mc_texture_class_init(McTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate=populate;
  G_OBJECT_CLASS(klass)->finalize=texture_finalize;
}
static void mc_texture_init(McTexture* self) {self->mutex=new std::mutex;self->decoder=nullptr;self->name=0;self->image={};self->gpu=new McLinuxGpuTexture;}
namespace {
// ALSA is loaded at runtime, keeping the plugin usable on systems where audio
// is unavailable. Nonblocking writes and bounded waits keep disposal bounded.
class Audio {
 public:
  Audio() {
    library_=dlopen("libasound.so.2",RTLD_NOW|RTLD_LOCAL);if(!library_)return;
    open_=symbol<Open>("snd_pcm_open");params_=symbol<Params>("snd_pcm_set_params");
    write_=symbol<Write>("snd_pcm_writei");recover_=symbol<Recover>("snd_pcm_recover");
    wait_=symbol<Wait>("snd_pcm_wait");close_=symbol<Close>("snd_pcm_close");drop_=symbol<Close>("snd_pcm_drop");
    if(!open_||!params_||!write_||!recover_||!wait_||!close_||!drop_)return;
    if(open_(&pcm_,"default",0,1)<0) {pcm_=nullptr;return;}
    if(params_(pcm_,2,3,2,48000,1,20000)<0) {close_(pcm_);pcm_=nullptr;}
  }
  ~Audio(){if(pcm_){drop_(pcm_);close_(pcm_);}if(library_)dlclose(library_);}
  bool ready()const{return pcm_!=nullptr;}
  int64_t write(const uint8_t* bytes,size_t length) {
    if(!pcm_)return -1;
    size_t frames=length/4;size_t original=frames;
    auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(80);
    while(frames) {
      long count=write_(pcm_,bytes,frames);
      if(count>0){bytes+=count*4;frames-=count;}
      else if(count==-11){if(std::chrono::steady_clock::now()>=deadline)break;wait_(pcm_,5);}
      else if(recover_(pcm_,static_cast<int>(count),1)<0)return -1;
    }
    return static_cast<int64_t>((original-frames)*4);
  }
 private:
  template<class T>T symbol(const char* name){return reinterpret_cast<T>(dlsym(library_,name));}
  using Open=int(*)(void**,const char*,int,int);using Params=int(*)(void*,int,int,unsigned,unsigned,int,unsigned);
  using Write=long(*)(void*,const void*,unsigned long);using Recover=int(*)(void*,int,int);using Wait=int(*)(void*,int);using Close=int(*)(void*);
  void* library_=nullptr;void* pcm_=nullptr;Open open_=nullptr;Params params_=nullptr;Write write_=nullptr;Recover recover_=nullptr;Wait wait_=nullptr;Close close_=nullptr,drop_=nullptr;
};
struct Output {
  FlTextureRegistrar* registrar=nullptr;
  McTexture* texture=nullptr;
  mc_decoder* decoder=nullptr;
  std::unique_ptr<Audio> audio;
  bool paused=false;
  ~Output(){
    if(texture){std::lock_guard<std::mutex> lock(*texture->mutex);texture->decoder=nullptr;}
    mc_destroy(decoder);
    if(texture){fl_texture_registrar_unregister_texture(registrar,FL_TEXTURE(texture));g_object_unref(texture);}
  }
};
struct Plugin {FlTextureRegistrar* registrar;std::unordered_map<int64_t,std::unique_ptr<Output>> outputs;int64_t next=1;};
FlValue* get(FlValue* args,const char* key){return args&&fl_value_get_type(args)==FL_VALUE_TYPE_MAP?fl_value_lookup_string(args,key):nullptr;}
int64_t integer(FlValue* args,const char* key,int64_t fallback=0){auto* v=get(args,key);return v&&fl_value_get_type(v)==FL_VALUE_TYPE_INT?fl_value_get_int(v):fallback;}
std::string string(FlValue* args,const char* key){auto* v=get(args,key);return v&&fl_value_get_type(v)==FL_VALUE_TYPE_STRING?fl_value_get_string(v):"";}
uint32_t codec_number(const std::string& codec){if(codec=="h264")return 1;if(codec=="h265"||codec=="hevc")return 2;if(codec=="av1")return 3;if(codec=="vp8")return 4;if(codec=="vp9")return 5;if(codec=="pcm_s16le"||codec=="raw")return 100;return 0;}
void put(FlValue* map,const char* key,FlValue* value){fl_value_set_string_take(map,key,value);}
void ready(void* user){auto* output=static_cast<Output*>(user);if(output->texture)fl_texture_registrar_mark_texture_frame_available(output->registrar,FL_TEXTURE(output->texture));}
int64_t pcm(void* user,const uint8_t* data,size_t len){auto* output=static_cast<Output*>(user);return output->audio?output->audio->write(data,len):-1;}
void respond(FlMethodCall* call,FlValue* value){g_autoptr(FlMethodResponse)response=FL_METHOD_RESPONSE(fl_method_success_response_new(value));fl_method_call_respond(call,response,nullptr);}
void error(FlMethodCall* call,const char* code,const char* message){g_autoptr(FlMethodResponse)response=FL_METHOD_RESPONSE(fl_method_error_response_new(code,message,nullptr));fl_method_call_respond(call,response,nullptr);}
void method(FlMethodChannel*,FlMethodCall* call,gpointer user) {
  auto* plugin=static_cast<Plugin*>(user);const char* name=fl_method_call_get_name(call);auto* args=fl_method_call_get_args(call);
  if(strcmp(name,"createVideo")==0||strcmp(name,"createAudio")==0) {
    bool audio=strcmp(name,"createAudio")==0;
    auto output=std::make_unique<Output>();output->registrar=plugin->registrar;
    if(audio){output->audio=std::make_unique<Audio>();if(!output->audio->ready()){error(call,"audio_unavailable","Unable to open the system audio output");return;}}
    else {output->texture=reinterpret_cast<McTexture*>(g_object_new(mc_texture_get_type(),nullptr));if(!fl_texture_registrar_register_texture(plugin->registrar,FL_TEXTURE(output->texture))){error(call,"texture_unavailable","Unable to register texture");return;}}
    mc_config config{};config.struct_size=sizeof(config);config.codec=audio?100:codec_number(string(args,"codec"));
    config.width=integer(args,"width");config.height=integer(args,"height");config.generation=integer(args,"generation");
    config.user=output.get();config.frame_ready=ready;config.pcm=pcm;
    output->decoder=mc_create(&config);if(output->texture)output->texture->decoder=output->decoder;
    auto source=string(args,"sourceId");
    if(!output->decoder||mc_attach(output->decoder,source.c_str(),integer(args,"attachAddress"),integer(args,"detachAddress"))!=0){error(call,"attach_failed","Unable to attach the remote media source");return;}
    int64_t handle=plugin->next++;g_autoptr(FlValue)result=fl_value_new_map();put(result,"handle",fl_value_new_int(handle));
    put(result,"textureId",fl_value_new_int(output->texture?fl_texture_get_id(FL_TEXTURE(output->texture)):-1));
    put(result,"width",fl_value_new_int(config.width));put(result,"height",fl_value_new_int(config.height));
    plugin->outputs.emplace(handle,std::move(output));respond(call,result);return;
  }
  auto found=plugin->outputs.find(integer(args,"handle"));
  if(found==plugin->outputs.end()){if(strcmp(name,"dispose")==0){respond(call,nullptr);return;}error(call,"unknown_handle","Media output no longer exists");return;}
  auto* output=found->second.get();
  if(strcmp(name,"dispose")==0){plugin->outputs.erase(found);respond(call,nullptr);return;}
  if(strcmp(name,"setPaused")==0){auto* value=get(args,"paused");output->paused=value&&fl_value_get_bool(value);mc_set_paused(output->decoder,output->paused);respond(call,nullptr);return;}
  if(strcmp(name,"setVolume")==0){auto* value=get(args,"volume");double volume=value?(fl_value_get_type(value)==FL_VALUE_TYPE_FLOAT?fl_value_get_float(value):fl_value_get_int(value)):1;mc_set_volume(output->decoder,volume);respond(call,nullptr);return;}
  if(strcmp(name,"status")==0){mc_status status{};mc_get_status(output->decoder,&status);g_autoptr(FlValue)result=fl_value_new_map();
    put(result,"width",fl_value_new_int(status.width));put(result,"height",fl_value_new_int(status.height));put(result,"frameCount",fl_value_new_int(status.frame_count));
    put(result,"bytesWritten",fl_value_new_int(status.bytes_written));put(result,"positionMs",fl_value_new_int(status.position_us/1000));
    put(result,"decoderName",fl_value_new_string(status.decoder_name));put(result,"hardwareAccelerated",fl_value_new_bool(status.hardware_accelerated));
    put(result,"nativeReady",fl_value_new_bool(status.native_ready));put(result,"ended",fl_value_new_bool(status.ended));put(result,"paused",fl_value_new_bool(output->paused));
    put(result,"errorCode",fl_value_new_int(status.error_code));put(result,"error",fl_value_new_string(status.error));respond(call,result);return;}
  if(strcmp(name,"snapshot")==0){mc_image image{};if(mc_copy_rgba_scaled(output->decoder,integer(args,"width"),integer(args,"height"),&image)!=0){respond(call,nullptr);return;}
    g_autoptr(FlValue)result=fl_value_new_map();put(result,"width",fl_value_new_int(image.width));put(result,"height",fl_value_new_int(image.height));
    put(result,"rgba",fl_value_new_uint8_list(image.rgba,image.size));mc_image_free(&image);respond(call,result);return;}
  g_autoptr(FlMethodResponse)response=FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());fl_method_call_respond(call,response,nullptr);
}
}
void media_codec_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin=new Plugin{fl_plugin_registrar_get_texture_registrar(registrar),{},1};
  g_autoptr(FlStandardMethodCodec)codec=fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel)channel=fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),"media_codec",FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel,method,plugin,[](gpointer p){delete static_cast<Plugin*>(p);});
}
