#include "../native/media_codec.h"
#include "include/media_codec/media_codec_plugin_c_api.h"
#include <Windows.h>
#include <algorithm>
#include <audioclient.h>
#include <chrono>
#include <cstring>
#include <d3d11.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <memory>
#include <mmdeviceapi.h>
#include <mutex>
#include <string>
#include <unordered_map>
#include <wrl/client.h>
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
}
using Microsoft::WRL::ComPtr;
namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
const Value *get(const Map &map, const char *key) {
  auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}
int64_t integer(const Map &map, const char *key, int64_t fallback = 0) {
  auto *v = get(map, key);
  if (!v)
    return fallback;
  if (auto *n = std::get_if<int64_t>(v))
    return *n;
  if (auto *n = std::get_if<int32_t>(v))
    return *n;
  return fallback;
}
std::string string(const Map &map, const char *key) {
  auto *v = get(map, key);
  auto *s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : "";
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
  return 0;
}
class Audio {
public:
  ~Audio() { shutdown(); }
  void shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);
    // Called by the PCM worker before it exits its COM apartment. WASAPI
    // service interfaces must be released on their GetService thread.
    invalidate();
    enumerator_.Reset();
    if (event_) {
      CloseHandle(event_);
      event_ = nullptr;
    }
  }
  void pause(bool value) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (paused_ == value)
      return;
    paused_ = value;
    if (client_) {
      HRESULT result = client_->Stop();
      if (SUCCEEDED(result))
        result = client_->Reset();
      if (SUCCEEDED(result) && !value)
        result = client_->Start();
      if (FAILED(result))
        invalidate();
    }
    submitted_ = 0;
    ++generation_;
  }
  int state(mc_audio_state *state) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!client_ || !clock_)
      return -1;
    UINT64 position = 0, ignored = 0;
    UINT32 queued = 0;
    if (FAILED(clock_->GetPosition(&position, &ignored)) ||
        FAILED(client_->GetCurrentPadding(&queued)))
      return -1;
    state->played_frames = std::min<uint64_t>(
        submitted_, static_cast<uint64_t>(static_cast<long double>(position) *
                                          48000 / frequency_));
    state->queued_frames = queued;
    state->generation = generation_;
    state->running = !paused_;
    return 0;
  }
  int64_t write(const uint8_t *data, size_t length) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (paused_)
      return 0;
    if ((!client_ || route_changed()) && !initialize())
      return -1;
    auto deadline =
        std::chrono::steady_clock::now() + std::chrono::milliseconds(80);
    size_t remaining = length / 4, original = remaining;
    while (remaining && std::chrono::steady_clock::now() < deadline) {
      UINT32 padding = 0;
      if (FAILED(client_->GetCurrentPadding(&padding))) {
        invalidate();
        break;
      }
      UINT32 available = capacity_ - std::min(capacity_, padding);
      UINT32 count =
          static_cast<UINT32>(std::min<size_t>(remaining, available));
      if (!count) {
        WaitForSingleObject(event_, 5);
        continue;
      }
      BYTE *buffer = nullptr;
      if (FAILED(render_->GetBuffer(count, &buffer))) {
        invalidate();
        break;
      }
      memcpy(buffer, data, count * 4);
      if (FAILED(render_->ReleaseBuffer(count, 0))) {
        invalidate();
        break;
      }
      data += count * 4;
      remaining -= count;
      submitted_ += count;
    }
    // Preserve a successful prefix; Rust retries precisely the unwritten tail.
    return original == remaining && !client_
               ? -1
               : static_cast<int64_t>((original - remaining) * 4);
  }

private:
  void invalidate() {
    if (client_)
      client_->Stop();
    render_.Reset();
    clock_.Reset();
    client_.Reset();
    submitted_ = 0;
    ++generation_;
  }
  bool route_changed() {
    auto now = std::chrono::steady_clock::now();
    if (now < route_check_)
      return false;
    route_check_ = now + std::chrono::seconds(1);
    ComPtr<IMMDevice> device;
    if (!enumerator_ || FAILED(enumerator_->GetDefaultAudioEndpoint(
                            eRender, eConsole, &device)))
      return false;
    LPWSTR id = nullptr;
    if (FAILED(device->GetId(&id)))
      return false;
    bool changed = endpoint_ != id;
    CoTaskMemFree(id);
    return changed;
  }
  bool initialize() {
    struct Apartment {
      HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      ~Apartment() {
        if (SUCCEEDED(result))
          CoUninitialize();
      }
    };
    static thread_local Apartment apartment;
    (void)apartment;
    invalidate();
    ComPtr<IMMDevice> device;
    if ((!enumerator_ &&
         FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                 CLSCTX_ALL, IID_PPV_ARGS(&enumerator_)))) ||
        FAILED(
            enumerator_->GetDefaultAudioEndpoint(eRender, eConsole, &device)) ||
        FAILED(device->Activate(
            __uuidof(IAudioClient), CLSCTX_ALL, nullptr,
            reinterpret_cast<void **>(client_.GetAddressOf()))))
      return false;
    LPWSTR id = nullptr;
    if (SUCCEEDED(device->GetId(&id))) {
      endpoint_ = id;
      CoTaskMemFree(id);
    }
    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 2;
    format.nSamplesPerSec = 48000;
    format.wBitsPerSample = 16;
    format.nBlockAlign = 4;
    format.nAvgBytesPerSec = 192000;
    if (!event_)
      event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event_) {
      invalidate();
      return false;
    }
    ResetEvent(event_);
    if (FAILED(client_->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                   AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                       AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                       AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                                   0, 0, &format, nullptr)) ||
        FAILED(client_->SetEventHandle(event_)) ||
        FAILED(client_->GetBufferSize(&capacity_)) ||
        FAILED(client_->GetService(IID_PPV_ARGS(&render_))) ||
        FAILED(client_->GetService(IID_PPV_ARGS(&clock_))) ||
        FAILED(clock_->GetFrequency(&frequency_)) || !frequency_ ||
        FAILED(client_->Start())) {
      invalidate();
      return false;
    }
    route_check_ = std::chrono::steady_clock::now() + std::chrono::seconds(1);
    return true;
  }
  ComPtr<IMMDeviceEnumerator> enumerator_;
  ComPtr<IAudioClient> client_;
  ComPtr<IAudioRenderClient> render_;
  ComPtr<IAudioClock> clock_;
  std::mutex mutex_;
  std::wstring endpoint_;
  std::chrono::steady_clock::time_point route_check_{};
  UINT32 capacity_ = 0;
  HANDLE event_ = nullptr;
  UINT64 frequency_ = 0;
  uint64_t submitted_ = 0, generation_ = 0;
  bool paused_ = false;
};
class GpuTexture {
public:
  void set_adapter(IDXGIAdapter *adapter) { render_adapter_ = adapter; }
  std::string hardware_device() const {
    if (!render_adapter_)
      return "";
    ComPtr<IDXGIFactory> factory;
    DXGI_ADAPTER_DESC desired{};
    if (FAILED(render_adapter_->GetParent(IID_PPV_ARGS(&factory))) ||
        FAILED(render_adapter_->GetDesc(&desired)))
      return "";
    for (UINT index = 0;; ++index) {
      ComPtr<IDXGIAdapter> candidate;
      if (FAILED(factory->EnumAdapters(index, &candidate)))
        break;
      DXGI_ADAPTER_DESC description{};
      if (SUCCEEDED(candidate->GetDesc(&description)) &&
          description.AdapterLuid.HighPart == desired.AdapterLuid.HighPart &&
          description.AdapterLuid.LowPart == desired.AdapterLuid.LowPart)
        return "d3d11va:" + std::to_string(index);
    }
    return "";
  }

  const FlutterDesktopGpuSurfaceDescriptor *update(mc_decoder *decoder) {
    mc_status current_status{};
    mc_get_status(decoder, &current_status);
    if (!output_ || rendered_frame_ != current_status.frame_count) {
      uint64_t sequence = 0;
      AVFrame *frame = mc_acquire_frame_snapshot(decoder, &sequence);
      if (!frame)
        return nullptr;
      bool converted = false;
      const bool readback = frame->hw_frames_ctx != nullptr;
      if (frame->format == AV_PIX_FMT_D3D11)
        converted = hardware(frame);
      if (!converted) {
        mc_image image{};
        if (mc_copy_frame_bgra(frame, &image) != 0) {
          mc_release_frame(frame);
          mc_report_present(decoder, sequence, "cpu/d3d11",
                            "Frame conversion failed");
          return nullptr;
        }
        bool uploaded = software(image);
        mc_image_free(&image);
        if (!uploaded) {
          mc_release_frame(frame);
          mc_report_present(decoder, sequence, "cpu/d3d11",
                            "D3D11 texture upload failed");
          return nullptr;
        }
      }
      mc_release_frame(frame);
      rendered_frame_ = sequence;
      mc_report_present(decoder, sequence,
                        converted ? "d3d11va/dxgi"
                                  : (readback ? "readback/dxgi" : "cpu/dxgi"),
                        nullptr);
    }
    descriptor_.struct_size = sizeof(descriptor_);
    descriptor_.handle = shared_handle_;
    descriptor_.width = width_;
    descriptor_.height = height_;
    descriptor_.visible_width = width_;
    descriptor_.visible_height = height_;
    descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
    // Flutter's ANGLE device differs from the decoder/upload device. Import
    // the DXGI shared handle, retaining its owner until Flutter has opened it.
    output_->AddRef();
    descriptor_.release_context = output_.Get();
    descriptor_.release_callback = [](void *p) {
      static_cast<ID3D11Texture2D *>(p)->Release();
    };
    return &descriptor_;
  }

private:
  bool can_share(ID3D11Device *device) {
    if (!render_adapter_)
      return true;
    if (probed_device_.Get() == device)
      return compatible_device_;
    probed_device_ = device;
    compatible_device_ = false;
    ComPtr<IDXGIDevice> dxgi_device;
    ComPtr<IDXGIAdapter> decoder_adapter;
    DXGI_ADAPTER_DESC decoder{}, renderer{};
    if (SUCCEEDED(device->QueryInterface(IID_PPV_ARGS(&dxgi_device))) &&
        SUCCEEDED(dxgi_device->GetAdapter(&decoder_adapter)) &&
        SUCCEEDED(decoder_adapter->GetDesc(&decoder)) &&
        SUCCEEDED(render_adapter_->GetDesc(&renderer)))
      compatible_device_ =
          decoder.AdapterLuid.HighPart == renderer.AdapterLuid.HighPart &&
          decoder.AdapterLuid.LowPart == renderer.AdapterLuid.LowPart;
    return compatible_device_;
  }

  bool target(ID3D11Device *device, UINT width, UINT height) {
    if (device_.Get() == device && output_ && width_ == width &&
        height_ == height)
      return true;
    output_.Reset();
    shared_handle_ = nullptr;
    processor_.Reset();
    output_view_.Reset();
    enumerator_.Reset();
    video_device_.Reset();
    video_context_.Reset();
    device_ = device;
    device_->GetImmediateContext(&context_);
    width_ = width;
    height_ = height;
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags =
        D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    description.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
    if (FAILED(device_->CreateTexture2D(&description, nullptr, &output_)))
      return false;
    ComPtr<IDXGIResource> resource;
    if (FAILED(output_.As(&resource)) ||
        FAILED(resource->GetSharedHandle(&shared_handle_))) {
      output_.Reset();
      return false;
    }
    return true;
  }
  bool hardware(AVFrame *frame) {
    if (frame->colorspace == AVCOL_SPC_BT2020_NCL ||
        frame->colorspace == AVCOL_SPC_BT2020_CL)
      return false;
    auto *input = reinterpret_cast<ID3D11Texture2D *>(frame->data[0]);
    if (!input)
      return false;
    ComPtr<ID3D11Device> device;
    input->GetDevice(&device);
    // Legacy DXGI sharing crosses devices on one adapter, not distinct GPUs.
    // Preserve decoding on the selected device and upload a CPU fallback on
    // Flutter's adapter when Windows chose different GPUs for the two APIs.
    if (!can_share(device.Get()))
      return false;
    auto *frames = reinterpret_cast<AVHWFramesContext *>(
        frame->hw_frames_ctx ? frame->hw_frames_ctx->data : nullptr);
    auto *hw = frames ? reinterpret_cast<AVD3D11VADeviceContext *>(
                            frames->device_ctx->hwctx)
                      : nullptr;
    if (hw && hw->lock)
      hw->lock(hw->lock_ctx);
    bool success = false;
    do {
      if (!target(device.Get(), frame->width, frame->height))
        break;
      if (!video_device_ && (FAILED(device_.As(&video_device_)) ||
                             FAILED(context_.As(&video_context_))))
        break;
      if (!enumerator_) {
        D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
        content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
        content.InputWidth = frame->width;
        content.InputHeight = frame->height;
        content.OutputWidth = frame->width;
        content.OutputHeight = frame->height;
        content.InputFrameRate = {60, 1};
        content.OutputFrameRate = {60, 1};
        content.Usage = D3D11_VIDEO_USAGE_OPTIMAL_SPEED;
        if (FAILED(video_device_->CreateVideoProcessorEnumerator(
                &content, &enumerator_)) ||
            FAILED(video_device_->CreateVideoProcessor(enumerator_.Get(), 0,
                                                       &processor_)))
          break;
      }
      D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC in{};
      in.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
      in.Texture2D.ArraySlice =
          static_cast<UINT>(reinterpret_cast<uintptr_t>(frame->data[1]));
      ComPtr<ID3D11VideoProcessorInputView> input_view;
      if (FAILED(video_device_->CreateVideoProcessorInputView(
              input, enumerator_.Get(), &in, &input_view)))
        break;
      D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC out{};
      out.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
      if (!output_view_ &&
          FAILED(video_device_->CreateVideoProcessorOutputView(
              output_.Get(), enumerator_.Get(), &out, &output_view_)))
        break;
      RECT rect{0, 0, frame->width, frame->height};
      video_context_->VideoProcessorSetStreamSourceRect(processor_.Get(), 0,
                                                        TRUE, &rect);
      video_context_->VideoProcessorSetStreamDestRect(processor_.Get(), 0, TRUE,
                                                      &rect);
      video_context_->VideoProcessorSetOutputTargetRect(processor_.Get(), TRUE,
                                                        &rect);
      D3D11_VIDEO_PROCESSOR_COLOR_SPACE color{};
      color.YCbCr_Matrix = frame->colorspace == AVCOL_SPC_BT709 ||
                           frame->colorspace == AVCOL_SPC_UNSPECIFIED;
      color.Nominal_Range = frame->color_range == AVCOL_RANGE_JPEG ? 2 : 1;
      video_context_->VideoProcessorSetStreamColorSpace(processor_.Get(), 0,
                                                        &color);
      D3D11_VIDEO_PROCESSOR_COLOR_SPACE output_color{};
      output_color.Nominal_Range = 2; // full-range RGB for Flutter BGRA8888
      video_context_->VideoProcessorSetOutputColorSpace(processor_.Get(),
                                                        &output_color);
      video_context_->VideoProcessorSetStreamAutoProcessingMode(
          processor_.Get(), 0, FALSE);
      D3D11_VIDEO_PROCESSOR_STREAM stream{};
      stream.Enable = TRUE;
      stream.pInputSurface = input_view.Get();
      if (FAILED(video_context_->VideoProcessorBlt(
              processor_.Get(), output_view_.Get(), 0, 1, &stream)))
        break;
      context_->Flush();
      success = true;
    } while (false);
    if (hw && hw->unlock)
      hw->unlock(hw->lock_ctx);
    return success;
  }
  bool software(const mc_image &image) {
    if (!upload_device_) {
      UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
      D3D_FEATURE_LEVEL level;
      HRESULT created = D3D11CreateDevice(
          render_adapter_.Get(),
          render_adapter_ ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE,
          nullptr, flags, nullptr, 0, D3D11_SDK_VERSION, &upload_device_,
          &level, nullptr);
      if (FAILED(created) && !render_adapter_)
        created = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
                                    flags, nullptr, 0, D3D11_SDK_VERSION,
                                    &upload_device_, &level, nullptr);
      if (FAILED(created))
        return false;
    }
    if (!target(upload_device_.Get(), image.width, image.height))
      return false;
    // swscale converts directly to BGRA; no second full-frame CPU traversal.
    context_->UpdateSubresource(output_.Get(), 0, nullptr, image.rgba,
                                static_cast<UINT>(image.stride), 0);
    context_->Flush();
    return true;
  }
  ComPtr<ID3D11Device> device_, upload_device_;
  ComPtr<IDXGIAdapter> render_adapter_;
  ComPtr<ID3D11Device> probed_device_;
  bool compatible_device_ = false;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11Texture2D> output_;
  HANDLE shared_handle_ = nullptr;
  ComPtr<ID3D11VideoDevice> video_device_;
  ComPtr<ID3D11VideoContext> video_context_;
  ComPtr<ID3D11VideoProcessorEnumerator> enumerator_;
  ComPtr<ID3D11VideoProcessor> processor_;
  ComPtr<ID3D11VideoProcessorOutputView> output_view_;
  uint64_t rendered_frame_ = 0;
  UINT width_ = 0, height_ = 0;
  FlutterDesktopGpuSurfaceDescriptor descriptor_{};
};
struct Output {
  flutter::TextureRegistrar *registrar = nullptr;
  int64_t texture_id = -1;
  mc_decoder *decoder = nullptr;
  std::unique_ptr<flutter::TextureVariant> texture;
  GpuTexture gpu;
  std::unique_ptr<Audio> audio;
  std::mutex mutex;
  void stop() {
    std::lock_guard<std::mutex> lock(mutex);
    mc_destroy(decoder);
    decoder = nullptr;
  }
  ~Output() { mc_destroy(decoder); }
};
class Plugin final : public flutter::Plugin {
public:
  explicit Plugin(flutter::PluginRegistrarWindows *registrar)
      : registrar_(registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<Value>>(
        registrar->messenger(), "media_codec",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto &call, auto result) {
      method(call, std::move(result));
    });
  }
  ~Plugin() override {
    for (auto &entry : outputs_)
      retire(std::move(entry.second));
  }

private:
  void retire(std::shared_ptr<Output> output) {
    output->stop();
    if (output->texture_id >= 0)
      registrar_->texture_registrar()->UnregisterTexture(output->texture_id,
                                                         [output] {});
  }
  void method(const flutter::MethodCall<Value> &call,
              std::unique_ptr<flutter::MethodResult<Value>> result) {
    Map empty;
    auto *arguments =
        call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    const Map &args = arguments ? *arguments : empty;
    auto &name = call.method_name();
    if (name == "createVideo" || name == "createAudio") {
      bool audio = name == "createAudio";
      auto output = std::make_shared<Output>();
      output->registrar = registrar_->texture_registrar();
      if (audio)
        output->audio = std::make_unique<Audio>();
      else {
        ComPtr<IDXGIAdapter> adapter;
        registrar_->GetGraphicsAdapter(&adapter);
        output->gpu.set_adapter(adapter.Get());
        auto *raw = output.get();
        output->texture = std::make_unique<flutter::TextureVariant>(
            flutter::GpuSurfaceTexture(
                kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
                [raw](size_t, size_t) {
                  std::lock_guard<std::mutex> lock(raw->mutex);
                  return raw->decoder ? raw->gpu.update(raw->decoder) : nullptr;
                }));
        output->texture_id =
            output->registrar->RegisterTexture(output->texture.get());
        if (output->texture_id < 0) {
          result->Error("texture_unavailable", "Unable to register texture");
          return;
        }
      }
      mc_config config{};
      config.struct_size = sizeof(config);
      config.codec = audio ? 100 : codec_number(string(args, "codec"));
      config.width = static_cast<uint32_t>(integer(args, "width"));
      config.height = static_cast<uint32_t>(integer(args, "height"));
      config.generation = integer(args, "generation");
      // FFmpeg's D3D11VA numeric device selects the DXGI adapter ordinal.
      std::string hardware_device = audio ? "" : output->gpu.hardware_device();
      config.hardware_device =
          hardware_device.empty() ? nullptr : hardware_device.c_str();
      config.user = output.get();
      config.frame_ready = [](void *p) {
        auto *o = static_cast<Output *>(p);
        o->registrar->MarkTextureFrameAvailable(o->texture_id);
      };
      config.pcm = [](void *p, const uint8_t *bytes, size_t length) -> int64_t {
        auto *o = static_cast<Output *>(p);
        return o->audio ? o->audio->write(bytes, length) : -1;
      };
      config.audio_pause = [](void *p, int32_t paused) {
        auto *o = static_cast<Output *>(p);
        if (o->audio)
          o->audio->pause(paused != 0);
      };
      config.audio_state = [](void *p, mc_audio_state *state) -> int32_t {
        auto *o = static_cast<Output *>(p);
        return o->audio ? o->audio->state(state) : -1;
      };
      config.audio_close = [](void *p) {
        auto *o = static_cast<Output *>(p);
        if (o->audio)
          o->audio->shutdown();
      };
      output->decoder = mc_create(&config);
      auto source = string(args, "sourceId");
      if (!output->decoder ||
          mc_attach(output->decoder, source.c_str(),
                    static_cast<uintptr_t>(integer(args, "attachAddress")),
                    static_cast<uintptr_t>(integer(args, "detachAddress"))) !=
              0) {
        retire(output);
        result->Error("attach_failed",
                      "Unable to attach the remote media source");
        return;
      }
      int64_t handle = next_++;
      Map reply{{Value("handle"), Value(handle)},
                {Value("textureId"), Value(output->texture_id)},
                {Value("width"), Value(static_cast<int64_t>(config.width))},
                {Value("height"), Value(static_cast<int64_t>(config.height))}};
      reply[Value("decoderAddress")] = Value(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(output->decoder)));
      reply[Value("nativeApi")] =
          Value(Map{{Value("getStatusAddress"),
                     Value(static_cast<int64_t>(
                         reinterpret_cast<intptr_t>(&mc_get_status)))},
                    {Value("setPausedAddress"),
                     Value(static_cast<int64_t>(
                         reinterpret_cast<intptr_t>(&mc_set_paused)))},
                    {Value("setVolumeAddress"),
                     Value(static_cast<int64_t>(
                         reinterpret_cast<intptr_t>(&mc_set_volume)))}});
      outputs_[handle] = output;
      result->Success(Value(reply));
      return;
    }
    auto found = outputs_.find(integer(args, "handle"));
    if (found == outputs_.end()) {
      if (name == "dispose")
        result->Success();
      else
        result->Error("unknown_handle", "Media output no longer exists");
      return;
    }
    auto output = found->second;
    if (name == "dispose") {
      outputs_.erase(found);
      retire(output);
      result->Success();
      return;
    }
    if (name == "snapshot") {
      mc_image image{};
      if (mc_copy_rgba_scaled(
              output->decoder, static_cast<uint32_t>(integer(args, "width")),
              static_cast<uint32_t>(integer(args, "height")), &image) != 0) {
        result->Success();
        return;
      }
      std::vector<uint8_t> bytes(image.rgba, image.rgba + image.size);
      Map reply{{Value("width"), Value(static_cast<int64_t>(image.width))},
                {Value("height"), Value(static_cast<int64_t>(image.height))},
                {Value("rgba"), Value(bytes)}};
      mc_image_free(&image);
      result->Success(Value(reply));
      return;
    }
    result->NotImplemented();
  }
  flutter::PluginRegistrarWindows *registrar_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::unordered_map<int64_t, std::shared_ptr<Output>> outputs_;
  int64_t next_ = 1;
};
} // namespace
void MediaCodecPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto *wrapper =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  wrapper->AddPlugin(std::make_unique<Plugin>(wrapper));
}
