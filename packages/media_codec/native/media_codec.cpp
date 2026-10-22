#include "media_codec.h"
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/buffer.h>
#include <libavutil/error.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
#if defined(__ANDROID__)
#include <libavcodec/mediacodec.h>
#include <libavutil/hwcontext_mediacodec.h>
#include <libavutil/opt.h>
#endif
}
namespace {
constexpr size_t kMaxBytes = 8 * 1024 * 1024;
constexpr size_t kMaxPackets = 8;
struct Packet { uint32_t event, codec, width, height, flags; int64_t pts; std::vector<uint8_t> data; };
AVCodecID codec_id(uint32_t codec) {
  switch (codec) { case 1:return AV_CODEC_ID_H264; case 2:return AV_CODEC_ID_HEVC;
    case 3:return AV_CODEC_ID_AV1; case 4:return AV_CODEC_ID_VP8; case 5:return AV_CODEC_ID_VP9;
    default:return AV_CODEC_ID_NONE; }
}
}
struct mc_decoder {
  mc_config config{};
  std::string requested_device, source;
  mc_detach_fn detach = nullptr;
  std::mutex mutex;
  std::condition_variable wake;
  std::deque<Packet> packets;
  size_t queued_bytes=0;
  bool stopping=false, attached=false;
  std::atomic<bool> paused{false};
  std::atomic<double> volume{1.0};
  std::thread worker;
  mc_status status{};
  AVCodecContext* codec=nullptr;
  AVBufferRef* hardware=nullptr;
  AVPixelFormat hardware_format=AV_PIX_FMT_NONE;
  AVFrame* latest=nullptr;
  std::mutex conversion_mutex;
  SwsContext* scaler=nullptr;
  std::vector<uint8_t> extra;
  std::deque<Packet> history;
  size_t history_bytes=0;
  bool hardware_failed=false;
  ~mc_decoder() {
    if(codec) avcodec_free_context(&codec);
    av_buffer_unref(&hardware);
    av_frame_free(&latest);
    sws_freeContext(scaler);
  }
};
namespace {
void set_error(mc_decoder* d,int error,const char* stage) {
  char reason[AV_ERROR_MAX_STRING_SIZE]{}; av_strerror(error,reason,sizeof(reason));
  std::lock_guard<std::mutex> lock(d->mutex);
  d->status.error_code=error;
  snprintf(d->status.error,sizeof(d->status.error),"%s: %s",stage,reason);
}
AVPixelFormat choose_format(AVCodecContext* context,const AVPixelFormat* formats) {
  auto* d=static_cast<mc_decoder*>(context->opaque);
  for(auto p=formats;*p!=AV_PIX_FMT_NONE;++p) if(*p==d->hardware_format) return *p;
  for(auto p=formats;*p!=AV_PIX_FMT_NONE;++p) {
    auto* description=av_pix_fmt_desc_get(*p);
    if(description && !(description->flags & AV_PIX_FMT_FLAG_HWACCEL)) return *p;
  }
  return AV_PIX_FMT_NONE;
}
void close_codec(mc_decoder* d) {
#if defined(__ANDROID__)

#endif
  avcodec_free_context(&d->codec); av_buffer_unref(&d->hardware);
  d->hardware_format=AV_PIX_FMT_NONE;
}
bool open_codec(mc_decoder* d,bool software) {
  close_codec(d);
  const AVCodec* implementation=avcodec_find_decoder(codec_id(d->config.codec));
  if(!implementation) { set_error(d,AVERROR_DECODER_NOT_FOUND,"decoder"); return false; }
#if defined(__ANDROID__)
  if(!software && d->config.native_window) {
    const char* name=nullptr;
    switch(d->config.codec) { case 1:name="h264_mediacodec";break;case 2:name="hevc_mediacodec";break;
      case 3:name="av1_mediacodec";break;case 4:name="vp8_mediacodec";break;case 5:name="vp9_mediacodec";break; }
    if(name) { auto* candidate=avcodec_find_decoder_by_name(name);if(candidate)implementation=candidate; }
  }
#endif
  d->codec=avcodec_alloc_context3(implementation);
  if(!d->codec) { set_error(d,AVERROR(ENOMEM),"allocate decoder");return false; }
  d->codec->width=static_cast<int>(d->config.width);d->codec->height=static_cast<int>(d->config.height);
  d->codec->pkt_timebase=AVRational{1,1000000};
  d->codec->flags|=AV_CODEC_FLAG_LOW_DELAY;
  d->codec->thread_count=1; d->codec->thread_type=FF_THREAD_SLICE;
  d->codec->opaque=d;
  if(!d->extra.empty()) {
    d->codec->extradata=static_cast<uint8_t*>(av_mallocz(d->extra.size()+AV_INPUT_BUFFER_PADDING_SIZE));
    if(!d->codec->extradata)return false;
    memcpy(d->codec->extradata,d->extra.data(),d->extra.size());
    d->codec->extradata_size=static_cast<int>(d->extra.size());
  }
  bool uses_hardware=false;
#if defined(__ANDROID__)
  if(!software && d->config.native_window && strstr(implementation->name,"mediacodec")) {
    d->hardware=av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_MEDIACODEC);
    if(!d->hardware)return open_codec(d,true);
    auto* device=reinterpret_cast<AVHWDeviceContext*>(d->hardware->data);
    auto* context=reinterpret_cast<AVMediaCodecDeviceContext*>(device->hwctx);
    context->native_window=d->config.native_window;
    if(av_hwdevice_ctx_init(d->hardware)<0)return open_codec(d,true);
    d->codec->hw_device_ctx=av_buffer_ref(d->hardware);
    av_opt_set_int(d->codec->priv_data,"ndk_codec",1,0);
    uses_hardware=true;
  }
#else
  if(!software && d->requested_device!="none") {
    std::vector<AVHWDeviceType> candidates;
    if(!d->requested_device.empty())candidates.push_back(av_hwdevice_find_type_by_name(d->requested_device.c_str()));
#if defined(_WIN32)
    else candidates={AV_HWDEVICE_TYPE_D3D11VA,AV_HWDEVICE_TYPE_DXVA2};
#elif defined(__APPLE__)
    else candidates={AV_HWDEVICE_TYPE_VIDEOTOOLBOX};
#else
    else candidates={AV_HWDEVICE_TYPE_VAAPI,AV_HWDEVICE_TYPE_CUDA,AV_HWDEVICE_TYPE_VULKAN};
#endif
    for(auto type:candidates) {
      for(int i=0;;++i) {
        auto* config=avcodec_get_hw_config(implementation,i);if(!config)break;
        if(config->device_type!=type || !(config->methods&AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX))continue;
        if(av_hwdevice_ctx_create(&d->hardware,type,nullptr,nullptr,0)<0)break;
        d->hardware_format=config->pix_fmt;
        d->codec->hw_device_ctx=av_buffer_ref(d->hardware);
        d->codec->get_format=choose_format;uses_hardware=true;break;
      }
      if(uses_hardware)break;
    }
  }
#endif
  int result=avcodec_open2(d->codec,implementation,nullptr);
  if(result<0) {
    if(!software)return open_codec(d,true);
    set_error(d,result,"open decoder");return false;
  }
  std::lock_guard<std::mutex> lock(d->mutex);
  d->status.error_code=0;d->status.error[0]=0;
  d->status.hardware_accelerated=uses_hardware;
  snprintf(d->status.decoder_name,sizeof(d->status.decoder_name),"%s%s%s",implementation->name,
    uses_hardware?"/":"",uses_hardware?(d->hardware?av_hwdevice_get_type_name(reinterpret_cast<AVHWDeviceContext*>(d->hardware->data)->type):"mediacodec"):"");
  return true;
}
void publish(mc_decoder* d,AVFrame* frame) {
#if defined(__ANDROID__)
  if(frame->format==AV_PIX_FMT_MEDIACODEC && frame->data[3])
    av_mediacodec_release_buffer(reinterpret_cast<AVMediaCodecBuffer*>(frame->data[3]),d->paused?0:1);
#endif
  {
    std::lock_guard<std::mutex> lock(d->mutex);
    av_frame_free(&d->latest);d->latest=av_frame_clone(frame);
    d->status.width=frame->width;d->status.height=frame->height;
    d->status.position_us=frame->pts==AV_NOPTS_VALUE?d->status.position_us:frame->pts;
    d->status.frame_count++;d->status.native_ready=1;d->status.error_code=0;d->status.error[0]=0;
    // The negotiated output determines actual acceleration, including a decoder
    // that silently selected its software pixel format.
    const AVPixFmtDescriptor* pixel=av_pix_fmt_desc_get(static_cast<AVPixelFormat>(frame->format));
    d->status.hardware_accelerated=pixel && (pixel->flags & AV_PIX_FMT_FLAG_HWACCEL);
  }
  if(!d->paused && d->config.frame_ready)d->config.frame_ready(d->config.user);
}
int decode_packet(mc_decoder* d,const Packet& packet) {
  AVPacket* input=av_packet_alloc();if(!input)return AVERROR(ENOMEM);
  int result=av_new_packet(input,static_cast<int>(packet.data.size()));
  if(result>=0) {
    memcpy(input->data,packet.data.data(),packet.data.size());input->pts=packet.pts;input->dts=AV_NOPTS_VALUE;
    if(packet.flags&1)input->flags|=AV_PKT_FLAG_KEY;
    result=avcodec_send_packet(d->codec,input);
  }
  av_packet_free(&input);if(result<0)return result;
  AVFrame* frame=av_frame_alloc();if(!frame)return AVERROR(ENOMEM);
  while((result=avcodec_receive_frame(d->codec,frame))>=0) { publish(d,frame);av_frame_unref(frame); }
  av_frame_free(&frame);
  return result==AVERROR(EAGAIN)||result==AVERROR_EOF?0:result;
}
void process_video(mc_decoder* d,Packet packet) {
  if(packet.event==1) {
    if(d->codec && d->config.codec==packet.codec && d->config.width==packet.width && d->config.height==packet.height && d->extra==packet.data)return;
    d->config.codec=packet.codec;d->config.width=packet.width;d->config.height=packet.height;
    d->extra=std::move(packet.data);d->history.clear();d->history_bytes=0;d->hardware_failed=false;
    open_codec(d,false);return;
  }
  if(!d->codec && !open_codec(d,d->hardware_failed))return;
  if(packet.flags&1) { d->history.clear();d->history_bytes=0; }
  if(d->history_bytes+packet.data.size()<=kMaxBytes) {
    d->history_bytes+=packet.data.size();d->history.push_back(packet);
  } else { d->history.clear();d->history_bytes=0; }
  int result=decode_packet(d,packet);
  if(result<0 && !d->hardware_failed) {
    d->hardware_failed=true;
    if(open_codec(d,true)) {
      if(d->history.empty())result=decode_packet(d,packet);
      else for(const auto& replay:d->history) {result=decode_packet(d,replay);if(result<0)break;}
    }
  }
  if(result<0)set_error(d,result,"decode packet");
}
void run(mc_decoder* d) {
  for(;;) {
    Packet packet;
    {
      std::unique_lock<std::mutex> lock(d->mutex);
      d->wake.wait(lock,[d]{return d->stopping||!d->packets.empty();});
      if(d->stopping)break;
      packet=std::move(d->packets.front());d->packets.pop_front();d->queued_bytes-=packet.data.size();
    }
    if(packet.event==3) { std::lock_guard<std::mutex> lock(d->mutex);d->status.ended=1;continue; }
    if(d->config.codec!=100) {process_video(d,std::move(packet));continue;}
    if(packet.event!=2 || d->paused)continue;
    double volume=d->volume.load();
    if(volume!=1.0)for(size_t i=0;i+1<packet.data.size();i+=2) {
      int16_t sample=static_cast<int16_t>(uint16_t(packet.data[i])|(uint16_t(packet.data[i+1])<<8));
      sample=static_cast<int16_t>(std::max(-32768.0,std::min(32767.0,sample*volume)));
      packet.data[i]=sample&255;packet.data[i+1]=(sample>>8)&255;
    }
    int64_t written=d->config.pcm?d->config.pcm(d->config.user,packet.data.data(),packet.data.size()):-1;
    if(written<0) {set_error(d,AVERROR_EXTERNAL,"audio output");continue;}
    std::lock_guard<std::mutex> lock(d->mutex);
    if(written>0) {
      d->status.bytes_written+=static_cast<uint64_t>(written);d->status.native_ready=1;
      d->status.error_code=0;d->status.error[0]=0;
      d->status.position_us=packet.pts+written*1000000/192000;
    }
  }
}
int32_t event(void* user,uint32_t kind,uint64_t generation,uint32_t codec,uint32_t width,uint32_t height,
              const uint8_t* data,size_t size,int64_t pts,uint32_t flags) {
  auto* d=static_cast<mc_decoder*>(user);
  if(generation!=d->config.generation || kind<1 || kind>3 || size>kMaxBytes || (size&&!data))return -1;
  std::lock_guard<std::mutex> lock(d->mutex);
  if(d->stopping)return -1;
  if(d->packets.size()>=kMaxPackets || d->queued_bytes+size>kMaxBytes)return 1;
  Packet packet{kind,codec,width,height,flags,pts,{}};
  if(size)packet.data.assign(data,data+size);
  d->queued_bytes+=size;d->packets.push_back(std::move(packet));d->wake.notify_one();return 0;
}
}
extern "C" {
mc_decoder* mc_create(const mc_config* config) {
  if(!config || config->struct_size<sizeof(mc_config) || (config->codec!=100 && codec_id(config->codec)==AV_CODEC_ID_NONE))return nullptr;
  auto d=std::make_unique<mc_decoder>();d->config=*config;
  if(config->hardware_device)d->requested_device=config->hardware_device;
  d->status.width=config->width;d->status.height=config->height;
  if(config->codec==100)snprintf(d->status.decoder_name,sizeof(d->status.decoder_name),"pcm_s16le");
  auto* result=d.release();result->worker=std::thread(run,result);return result;
}
int32_t mc_attach(mc_decoder* d,const char* source,uintptr_t attach_address,uintptr_t detach_address) {
  if(!d||!source||!attach_address||!detach_address||d->attached)return -1;
  d->source=source;d->detach=reinterpret_cast<mc_detach_fn>(detach_address);
  mc_sink_v1 sink{1,sizeof(mc_sink_v1),d,event};
  int result=reinterpret_cast<mc_attach_fn>(attach_address)(reinterpret_cast<const uint8_t*>(source),strlen(source),d->config.generation,&sink);
  d->attached=result==0;return result;
}
void mc_get_status(mc_decoder* d,mc_status* out) {if(!d||!out)return;std::lock_guard<std::mutex> lock(d->mutex);*out=d->status;}
void mc_set_paused(mc_decoder* d,int32_t paused) {
  if(!d)return;
  bool was=d->paused.exchange(paused!=0);
  if(was&&!paused&&d->config.frame_ready)d->config.frame_ready(d->config.user);
}
void mc_set_volume(mc_decoder* d,double volume) {if(d)d->volume=std::max(0.0,std::min(1.0,volume));}
AVFrame* mc_acquire_frame(mc_decoder* d) {if(!d)return nullptr;std::lock_guard<std::mutex> lock(d->mutex);return d->latest?av_frame_clone(d->latest):nullptr;}
void mc_release_frame(AVFrame* frame) {av_frame_free(&frame);}
int32_t mc_copy_rgba(mc_decoder* d,mc_image* out) {return mc_copy_rgba_scaled(d,0,0,out);}
int32_t mc_copy_rgba_scaled(mc_decoder* d,uint32_t max_width,uint32_t max_height,mc_image* out) {
  if(!d||!out)return -1;
  *out={};
  std::lock_guard<std::mutex> conversion(d->conversion_mutex);
  AVFrame* frame=mc_acquire_frame(d);if(!frame)return 1;
  AVFrame* software=nullptr;
  const auto* descriptor=av_pix_fmt_desc_get(static_cast<AVPixelFormat>(frame->format));
  if(descriptor && (descriptor->flags&AV_PIX_FMT_FLAG_HWACCEL)) {
    software=av_frame_alloc();int result=av_hwframe_transfer_data(software,frame,0);
    if(result<0) {av_frame_free(&frame);av_frame_free(&software);return result;}
  }
  AVFrame* source=software?software:frame;
  if(source->width<=0 || source->height<=0 || source->width>16384 || source->height>16384) {av_frame_free(&frame);av_frame_free(&software);return -1;}
  double scale=1.0;
  if(max_width && source->width>static_cast<int>(max_width))scale=std::min(scale,static_cast<double>(max_width)/source->width);
  if(max_height && source->height>static_cast<int>(max_height))scale=std::min(scale,static_cast<double>(max_height)/source->height);
  out->width=std::max(1,static_cast<int>(source->width*scale));out->height=std::max(1,static_cast<int>(source->height*scale));out->stride=static_cast<size_t>(out->width)*4;out->size=out->stride*out->height;
  out->rgba=static_cast<uint8_t*>(av_malloc(out->size));
  if(!out->rgba) {av_frame_free(&frame);av_frame_free(&software);return AVERROR(ENOMEM);}
  d->scaler=sws_getCachedContext(d->scaler,source->width,source->height,static_cast<AVPixelFormat>(source->format),out->width,out->height,AV_PIX_FMT_RGBA,SWS_FAST_BILINEAR,nullptr,nullptr,nullptr);
  int result=-1;
  if(d->scaler) {uint8_t* target[]={out->rgba};int stride[]={static_cast<int>(out->stride)};result=sws_scale(d->scaler,source->data,source->linesize,0,source->height,target,stride);}
  av_frame_free(&frame);av_frame_free(&software);
  if(result<0)mc_image_free(out);
  return result<0?result:0;
}
void mc_image_free(mc_image* image) {if(image){av_free(image->rgba);*image={};}}
void mc_destroy(mc_decoder* d) {
  if(!d)return;
  if(d->attached) {d->detach(reinterpret_cast<const uint8_t*>(d->source.data()),d->source.size(),d->config.generation);d->attached=false;}
  {std::lock_guard<std::mutex> lock(d->mutex);d->stopping=true;d->wake.notify_all();}
  if(d->worker.joinable())d->worker.join();
  close_codec(d);delete d;
}
}
