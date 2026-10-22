#include "include/media_codec/media_codec_plugin_c_api.h"
#include "../native/media_codec.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <Windows.h>
#include <audioclient.h>
#include <d3d11.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>
#include <algorithm>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
}
using Microsoft::WRL::ComPtr;
namespace {
using Value=flutter::EncodableValue;using Map=flutter::EncodableMap;
const Value* get(const Map& map,const char* key){auto found=map.find(Value(key));return found==map.end()?nullptr:&found->second;}
int64_t integer(const Map& map,const char* key,int64_t fallback=0){auto* v=get(map,key);if(!v)return fallback;if(auto* n=std::get_if<int64_t>(v))return *n;if(auto* n=std::get_if<int32_t>(v))return *n;return fallback;}
std::string string(const Map& map,const char* key){auto* v=get(map,key);auto* s=v?std::get_if<std::string>(v):nullptr;return s?*s:"";}
uint32_t codec_number(const std::string& codec){if(codec=="h264")return 1;if(codec=="h265"||codec=="hevc")return 2;if(codec=="av1")return 3;if(codec=="vp8")return 4;if(codec=="vp9")return 5;return 0;}
class Audio {
 public:
  bool initialize(){
    CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    ComPtr<IMMDeviceEnumerator> enumerator;ComPtr<IMMDevice> device;
    if(FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumerator)))||FAILED(enumerator->GetDefaultAudioEndpoint(eRender,eConsole,&device))||FAILED(device->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,reinterpret_cast<void**>(client_.GetAddressOf()))))return false;
    WAVEFORMATEX format{};format.wFormatTag=WAVE_FORMAT_PCM;format.nChannels=2;format.nSamplesPerSec=48000;format.wBitsPerSample=16;format.nBlockAlign=4;format.nAvgBytesPerSec=192000;
    if(FAILED(client_->Initialize(AUDCLNT_SHAREMODE_SHARED,AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM|AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,1000000,0,&format,nullptr)))return false;
    if(FAILED(client_->GetBufferSize(&capacity_))||FAILED(client_->GetService(IID_PPV_ARGS(&render_)))||FAILED(client_->Start()))return false;
    return true;
  }
  ~Audio(){if(client_)client_->Stop();}
  int64_t write(const uint8_t* data,size_t length){
    if(!initialized_){initialized_=true;ready_=initialize();}if(!ready_)return -1;
    auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(80);
    size_t remaining=length/4;size_t original=remaining;
    while(remaining){UINT32 padding=0;if(FAILED(client_->GetCurrentPadding(&padding)))break;
      UINT32 available=capacity_-std::min(capacity_,padding);
      UINT32 count=static_cast<UINT32>(std::min<size_t>(remaining,available));
      if(!count){if(std::chrono::steady_clock::now()>=deadline)break;Sleep(1);continue;}
      BYTE* buffer=nullptr;if(FAILED(render_->GetBuffer(count,&buffer)))break;
      memcpy(buffer,data,count*4);render_->ReleaseBuffer(count,0);data+=count*4;remaining-=count;
    }
    return static_cast<int64_t>((original-remaining)*4);
  }
 private:ComPtr<IAudioClient> client_;ComPtr<IAudioRenderClient> render_;UINT32 capacity_=0;bool initialized_=false,ready_=false;
};
class GpuTexture {
 public:
  const FlutterDesktopGpuSurfaceDescriptor* update(mc_decoder* decoder){
    AVFrame* frame=mc_acquire_frame(decoder);if(!frame)return nullptr;
    bool converted=false;
    if(frame->format==AV_PIX_FMT_D3D11)converted=hardware(frame);
    mc_release_frame(frame);
    if(!converted) {
      mc_image image{};if(mc_copy_rgba(decoder,&image)!=0)return nullptr;
      bool uploaded=software(image);mc_image_free(&image);if(!uploaded)return nullptr;
    }
    descriptor_.struct_size=sizeof(descriptor_);descriptor_.handle=output_.Get();
    descriptor_.width=width_;descriptor_.height=height_;descriptor_.visible_width=width_;descriptor_.visible_height=height_;
    descriptor_.format=kFlutterDesktopPixelFormatBGRA8888;
    // A reference is held until Flutter has opened the shared resource.
    output_->AddRef();descriptor_.release_context=output_.Get();descriptor_.release_callback=[](void* p){static_cast<ID3D11Texture2D*>(p)->Release();};
    return &descriptor_;
  }
 private:
  bool target(ID3D11Device* device,UINT width,UINT height){
    if(device_.Get()==device && output_ && width_==width && height_==height)return true;
    output_.Reset();processor_.Reset();enumerator_.Reset();video_device_.Reset();video_context_.Reset();
    device_=device;device_->GetImmediateContext(&context_);width_=width;height_=height;
    D3D11_TEXTURE2D_DESC description{};description.Width=width;description.Height=height;description.MipLevels=1;description.ArraySize=1;
    description.Format=DXGI_FORMAT_B8G8R8A8_UNORM;description.SampleDesc.Count=1;description.Usage=D3D11_USAGE_DEFAULT;
    description.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;description.MiscFlags=D3D11_RESOURCE_MISC_SHARED;
    return SUCCEEDED(device_->CreateTexture2D(&description,nullptr,&output_));
  }
  bool hardware(AVFrame* frame){
    auto* input=reinterpret_cast<ID3D11Texture2D*>(frame->data[0]);if(!input)return false;
    ComPtr<ID3D11Device> device;input->GetDevice(&device);
    auto* frames=reinterpret_cast<AVHWFramesContext*>(frame->hw_frames_ctx?frame->hw_frames_ctx->data:nullptr);
    auto* hw=frames?reinterpret_cast<AVD3D11VADeviceContext*>(frames->device_ctx->hwctx):nullptr;
    if(hw&&hw->lock)hw->lock(hw->lock_ctx);
    bool success=false;
    do {
      if(!target(device.Get(),frame->width,frame->height))break;
      if(!video_device_ && (FAILED(device_.As(&video_device_))||FAILED(context_.As(&video_context_))))break;
      if(!enumerator_){D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};content.InputFrameFormat=D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;content.InputWidth=frame->width;content.InputHeight=frame->height;content.OutputWidth=frame->width;content.OutputHeight=frame->height;content.InputFrameRate={60,1};content.OutputFrameRate={60,1};content.Usage=D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
        if(FAILED(video_device_->CreateVideoProcessorEnumerator(&content,&enumerator_))||FAILED(video_device_->CreateVideoProcessor(enumerator_.Get(),0,&processor_)))break;}
      D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC in{};in.ViewDimension=D3D11_VPIV_DIMENSION_TEXTURE2D;in.Texture2D.ArraySlice=static_cast<UINT>(reinterpret_cast<uintptr_t>(frame->data[1]));
      ComPtr<ID3D11VideoProcessorInputView> input_view;if(FAILED(video_device_->CreateVideoProcessorInputView(input,enumerator_.Get(),&in,&input_view)))break;
      D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC out{};out.ViewDimension=D3D11_VPOV_DIMENSION_TEXTURE2D;
      ComPtr<ID3D11VideoProcessorOutputView> output_view;if(FAILED(video_device_->CreateVideoProcessorOutputView(output_.Get(),enumerator_.Get(),&out,&output_view)))break;
      RECT rect{0,0,frame->width,frame->height};video_context_->VideoProcessorSetStreamSourceRect(processor_.Get(),0,TRUE,&rect);video_context_->VideoProcessorSetStreamDestRect(processor_.Get(),0,TRUE,&rect);video_context_->VideoProcessorSetOutputTargetRect(processor_.Get(),TRUE,&rect);
      D3D11_VIDEO_PROCESSOR_COLOR_SPACE color{};color.YCbCr_Matrix=frame->colorspace==AVCOL_SPC_BT709;video_context_->VideoProcessorSetStreamColorSpace(processor_.Get(),0,&color);
      D3D11_VIDEO_PROCESSOR_STREAM stream{};stream.Enable=TRUE;stream.pInputSurface=input_view.Get();
      if(FAILED(video_context_->VideoProcessorBlt(processor_.Get(),output_view.Get(),0,1,&stream)))break;
      context_->Flush();success=true;
    }while(false);
    if(hw&&hw->unlock)hw->unlock(hw->lock_ctx);return success;
  }
  bool software(const mc_image& image){
    if(!upload_device_){UINT flags=D3D11_CREATE_DEVICE_BGRA_SUPPORT;D3D_FEATURE_LEVEL level;
      if(FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,flags,nullptr,0,D3D11_SDK_VERSION,&upload_device_,&level,nullptr))&&FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,flags,nullptr,0,D3D11_SDK_VERSION,&upload_device_,&level,nullptr)))return false;}
    if(!target(upload_device_.Get(),image.width,image.height))return false;
    // The shared output is BGRA. CPU fallback alone needs channel conversion.
    pixels_.resize(image.size);for(size_t i=0;i<image.size;i+=4){pixels_[i]=image.rgba[i+2];pixels_[i+1]=image.rgba[i+1];pixels_[i+2]=image.rgba[i];pixels_[i+3]=image.rgba[i+3];}
    context_->UpdateSubresource(output_.Get(),0,nullptr,pixels_.data(),static_cast<UINT>(image.stride),0);context_->Flush();return true;
  }
  ComPtr<ID3D11Device> device_,upload_device_;ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11Texture2D> output_;ComPtr<ID3D11VideoDevice> video_device_;ComPtr<ID3D11VideoContext> video_context_;
  ComPtr<ID3D11VideoProcessorEnumerator> enumerator_;ComPtr<ID3D11VideoProcessor> processor_;
  UINT width_=0,height_=0;std::vector<uint8_t> pixels_;FlutterDesktopGpuSurfaceDescriptor descriptor_{};
};
struct Output {
  flutter::TextureRegistrar* registrar=nullptr;int64_t texture_id=-1;mc_decoder* decoder=nullptr;
  std::unique_ptr<flutter::TextureVariant> texture;GpuTexture gpu;std::unique_ptr<Audio> audio;std::mutex mutex;bool paused=false;
  void stop(){std::lock_guard<std::mutex> lock(mutex);mc_destroy(decoder);decoder=nullptr;}
  ~Output(){mc_destroy(decoder);}
};
class Plugin final:public flutter::Plugin {
 public:
  explicit Plugin(flutter::PluginRegistrarWindows* registrar):registrar_(registrar){
    channel_=std::make_unique<flutter::MethodChannel<Value>>(registrar->messenger(),"media_codec",&flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call,auto result){method(call,std::move(result));});
  }
  ~Plugin()override {for(auto& entry:outputs_)retire(std::move(entry.second));}
 private:
  void retire(std::shared_ptr<Output> output){output->stop();if(output->texture_id>=0)registrar_->texture_registrar()->UnregisterTexture(output->texture_id,[output]{});}
  void method(const flutter::MethodCall<Value>& call,std::unique_ptr<flutter::MethodResult<Value>> result){
    Map empty;auto* arguments=call.arguments()?std::get_if<Map>(call.arguments()):nullptr;const Map& args=arguments?*arguments:empty;auto& name=call.method_name();
    if(name=="createVideo"||name=="createAudio"){
      bool audio=name=="createAudio";auto output=std::make_shared<Output>();output->registrar=registrar_->texture_registrar();
      if(audio)output->audio=std::make_unique<Audio>();
      else {auto* raw=output.get();output->texture=std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(kFlutterDesktopGpuSurfaceTypeD3d11Texture2D,[raw](size_t,size_t){std::lock_guard<std::mutex> lock(raw->mutex);return raw->decoder?raw->gpu.update(raw->decoder):nullptr;}));output->texture_id=output->registrar->RegisterTexture(output->texture.get());if(output->texture_id<0){result->Error("texture_unavailable","Unable to register texture");return;}}
      mc_config config{};config.struct_size=sizeof(config);config.codec=audio?100:codec_number(string(args,"codec"));config.width=static_cast<uint32_t>(integer(args,"width"));config.height=static_cast<uint32_t>(integer(args,"height"));config.generation=integer(args,"generation");config.user=output.get();
      config.frame_ready=[](void* p){auto* o=static_cast<Output*>(p);o->registrar->MarkTextureFrameAvailable(o->texture_id);};
      config.pcm=[](void* p,const uint8_t* bytes,size_t length)->int64_t {auto* o=static_cast<Output*>(p);return o->audio?o->audio->write(bytes,length):-1;};
      output->decoder=mc_create(&config);auto source=string(args,"sourceId");
      if(!output->decoder||mc_attach(output->decoder,source.c_str(),static_cast<uintptr_t>(integer(args,"attachAddress")),static_cast<uintptr_t>(integer(args,"detachAddress")))!=0){retire(output);result->Error("attach_failed","Unable to attach the remote media source");return;}
      int64_t handle=next_++;Map reply{{Value("handle"),Value(handle)},{Value("textureId"),Value(output->texture_id)},{Value("width"),Value(static_cast<int64_t>(config.width))},{Value("height"),Value(static_cast<int64_t>(config.height))}};
      outputs_[handle]=output;result->Success(Value(reply));return;
    }
    auto found=outputs_.find(integer(args,"handle"));if(found==outputs_.end()){if(name=="dispose")result->Success();else result->Error("unknown_handle","Media output no longer exists");return;}
    auto output=found->second;
    if(name=="dispose"){outputs_.erase(found);retire(output);result->Success();return;}
    if(name=="setPaused"){auto* v=get(args,"paused");output->paused=v&&std::get_if<bool>(v)?std::get<bool>(*v):false;mc_set_paused(output->decoder,output->paused);result->Success();return;}
    if(name=="setVolume"){auto* v=get(args,"volume");double volume=v&&std::get_if<double>(v)?std::get<double>(*v):1;mc_set_volume(output->decoder,volume);result->Success();return;}
    if(name=="status"){mc_status s{};mc_get_status(output->decoder,&s);Map reply{{Value("width"),Value(static_cast<int64_t>(s.width))},{Value("height"),Value(static_cast<int64_t>(s.height))},{Value("frameCount"),Value(static_cast<int64_t>(s.frame_count))},{Value("bytesWritten"),Value(static_cast<int64_t>(s.bytes_written))},{Value("positionMs"),Value(s.position_us/1000)},{Value("decoderName"),Value(s.decoder_name)},{Value("hardwareAccelerated"),Value(s.hardware_accelerated!=0)},{Value("nativeReady"),Value(s.native_ready!=0)},{Value("ended"),Value(s.ended!=0)},{Value("paused"),Value(output->paused)},{Value("errorCode"),Value(s.error_code)},{Value("error"),Value(s.error)}};result->Success(Value(reply));return;}
    if(name=="snapshot"){mc_image image{};if(mc_copy_rgba_scaled(output->decoder,static_cast<uint32_t>(integer(args,"width")),static_cast<uint32_t>(integer(args,"height")),&image)!=0){result->Success();return;}std::vector<uint8_t> bytes(image.rgba,image.rgba+image.size);Map reply{{Value("width"),Value(static_cast<int64_t>(image.width))},{Value("height"),Value(static_cast<int64_t>(image.height))},{Value("rgba"),Value(bytes)}};mc_image_free(&image);result->Success(Value(reply));return;}
    result->NotImplemented();
  }
  flutter::PluginRegistrarWindows* registrar_;std::unique_ptr<flutter::MethodChannel<Value>> channel_;std::unordered_map<int64_t,std::shared_ptr<Output>> outputs_;int64_t next_=1;
};
}
void MediaCodecPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar){auto* wrapper=flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);wrapper->AddPlugin(std::make_unique<Plugin>(wrapper));}
