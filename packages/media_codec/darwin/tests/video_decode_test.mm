// Run against the Rust core and the pinned FFmpeg headers on an Apple host.
#include "media_codec.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}
#include <CoreVideo/CoreVideo.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
#include <thread>
#include <vector>
#include <cstdlib>

namespace {
mc_sink_v1 sink{};
bool detached = false;
void check(bool value, const char* message) {
  if (!value) { std::cerr << message << '\n'; std::abort(); }
}
int32_t attach(const uint8_t*, size_t, uint64_t, const mc_sink_v1* value) {
  sink = *value;
  return 0;
}
int32_t detach(const uint8_t*, size_t, uint64_t) { detached = true; return 0; }
void submit(uint32_t event, const uint8_t* data, size_t length, int64_t pts, uint32_t flags) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  for (;;) {
    const auto result = sink.event(sink.context, event, 7, 1, 320, 720, data, length, pts, flags);
    check(result >= 0, "packet rejected");
    if (!result) return;
    check(std::chrono::steady_clock::now() < deadline, "decoder queue stalled");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
}
int main(int argc, char** argv) {
  check(argc >= 2, "usage: video_decode_test android.h264 [none|videotoolbox]");
  std::ifstream input(argv[1], std::ios::binary);
  const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
  std::vector<std::pair<size_t,size_t>> starts;
  for (size_t index = 0; index + 3 < bytes.size();) {
    size_t prefix = 0;
    if (bytes[index] == 0 && bytes[index+1] == 0 && bytes[index+2] == 1) prefix = 3;
    else if (index + 4 < bytes.size() && bytes[index] == 0 && bytes[index+1] == 0 && bytes[index+2] == 0 && bytes[index+3] == 1) prefix = 4;
    if (prefix) { starts.emplace_back(index, prefix); index += prefix; } else ++index;
  }
  std::vector<uint8_t> configuration;
  std::vector<std::pair<std::vector<uint8_t>, bool>> packets;
  for (size_t index = 0; index < starts.size(); ++index) {
    const auto start = starts[index].first;
    const auto end = index + 1 < starts.size() ? starts[index+1].first : bytes.size();
    const int kind = bytes[start + starts[index].second] & 31;
    if (kind == 7 || kind == 8) configuration.insert(configuration.end(), bytes.begin()+start, bytes.begin()+end);
    if (kind == 1 || kind == 5) packets.emplace_back(std::vector<uint8_t>(bytes.begin()+start, bytes.begin()+end), kind == 5);
  }
  check(!configuration.empty() && !packets.empty(), "fixture lacks configuration/video");
  mc_config config{};
  config.struct_size = sizeof(config); config.codec = 1; config.generation = 7;
  config.width = 320; config.height = 720;
  config.hardware_device = argc > 2 ? argv[2] : "videotoolbox";
  auto* decoder = mc_create(&config);
  check(decoder, "create failed");
  check(mc_attach(decoder, "apple-h264", reinterpret_cast<uintptr_t>(&attach), reinterpret_cast<uintptr_t>(&detach)) == 0, "attach failed");
  const auto started = std::chrono::steady_clock::now();
  submit(1, configuration.data(), configuration.size(), 0, 2);
  size_t count = 0;
  for (const auto& packet : packets) submit(2, packet.first.data(), packet.first.size(), count++ * 33333, packet.second ? 1 : 0);
  submit(3, nullptr, 0, 0, 0);
  mc_status status{};
  do {
    mc_get_status(decoder, &status);
    check(std::chrono::steady_clock::now() - started < std::chrono::seconds(15), "decode timeout");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  } while (!status.ended);
  check(!status.error_code && status.frame_count > 0, "no decoded output");
  auto* frame = mc_acquire_frame(decoder);
  check(frame, "no texture frame");
  const bool pixelBuffer = frame->format == AV_PIX_FMT_VIDEOTOOLBOX && frame->data[3];
  if (status.hardware_accelerated) {
    check(pixelBuffer, "hardware output did not retain a CVPixelBuffer");
    auto buffer = reinterpret_cast<CVPixelBufferRef>(frame->data[3]);
    check(CVPixelBufferGetWidth(buffer) == status.width && CVPixelBufferGetHeight(buffer) == status.height, "pixel buffer dimensions differ");
  }
  mc_release_frame(frame);
  mc_image image{};
  check(mc_copy_rgba_scaled(decoder, 32, 32, &image) == 0, "snapshot failed");
  check(image.width && image.height && image.width <= 32 && image.height <= 32, "snapshot dimensions invalid");
  bool colored = false;
  for (size_t i = 0; i < image.size; i += 4) {
    check(image.rgba[i+3] == 255, "snapshot alpha invalid");
    colored |= image.rgba[i] || image.rgba[i+1] || image.rgba[i+2];
  }
  check(colored, "snapshot is black");
  const auto elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
  std::cout << "Apple H264 packets=" << packets.size() << " frames=" << status.frame_count << " decoder=" << status.decoder_name << " hardware=" << status.hardware_accelerated << " pixelBuffer=" << pixelBuffer << " elapsedMs=" << elapsed << " size=" << status.width << "x" << status.height << " snapshot=" << image.width << "x" << image.height << '\n';
  mc_image_free(&image);
  mc_set_paused(decoder, 1); mc_get_status(decoder, &status); check(status.paused, "pause ABI failed");
  mc_set_paused(decoder, 0); mc_destroy(decoder); check(detached, "dispose did not drain detach");
}
