#include "media_codec.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <thread>
#include <vector>

namespace {
mc_sink_v1 sink{};
bool detached = false;
void check(bool value, const char *message) {
  if (!value) {
    std::cerr << message << '\n';
    std::abort();
  }
}
int32_t attach(const uint8_t *, size_t, uint64_t, const mc_sink_v1 *value) {
  sink = *value;
  return 0;
}
int32_t detach(const uint8_t *, size_t, uint64_t) {
  detached = true;
  return 0;
}
uint32_t little(const uint8_t *data, size_t length) {
  uint32_t result = 0;
  for (size_t index = 0; index < length; ++index)
    result |= uint32_t(data[index]) << (index * 8);
  return result;
}
void submit(uint32_t event, uint32_t width, uint32_t height,
            const uint8_t *data, size_t length, int64_t pts, uint32_t flags) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  for (;;) {
    const int result = sink.event(sink.context, event, 7, 3, width, height,
                                  data, length, pts, flags);
    check(result >= 0, "input rejected");
    if (result == 0)
      return;
    check(std::chrono::steady_clock::now() < deadline, "input queue stalled");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
} // namespace

// IVF 仅作为测试夹具封装；生产库直接接收原始 AV1 包负载，
// 不包含解复用器或 AVFormat。
int main(int argc, char **argv) {
  check(argc == 2 || argc == 3,
        "usage: video_decode_test AV1.ivf [required-hardware-device]");
  const bool require_hardware = argc == 3;
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
  check(bytes.size() >= 32 &&
            std::string(bytes.begin(), bytes.begin() + 4) == "DKIF",
        "invalid IVF fixture");
  check(std::string(bytes.begin() + 8, bytes.begin() + 12) == "AV01",
        "expected AV1");
  const uint32_t width = little(bytes.data() + 12, 2);
  const uint32_t height = little(bytes.data() + 14, 2);
  mc_config config{};
  config.struct_size = sizeof(config);
  config.codec = 3;
  config.width = width;
  config.height = height;
  config.generation = 7;
  config.hardware_device = require_hardware ? argv[2] : "none";
  mc_decoder *decoder = mc_create(&config);
  check(decoder, "create failed");
  check(mc_attach(decoder, "av1-fixture", reinterpret_cast<uintptr_t>(&attach),
                  reinterpret_cast<uintptr_t>(&detach)) == 0,
        "attach failed");
  submit(1, width, height, nullptr, 0, 0, 2);
  size_t offset = little(bytes.data() + 6, 2);
  uint64_t packets = 0;
  while (offset < bytes.size()) {
    check(offset + 12 <= bytes.size(), "truncated packet header");
    const auto size = little(bytes.data() + offset, 4);
    offset += 12;
    check(size <= bytes.size() - offset, "truncated packet");
    submit(2, width, height, bytes.data() + offset, size,
           static_cast<int64_t>(packets * 33333), packets == 0 ? 1 : 0);
    offset += size;
    ++packets;
  }
  submit(3, width, height, nullptr, 0, 0, 0);
  mc_status status{};
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(10);
  do {
    mc_get_status(decoder, &status);
    check(std::chrono::steady_clock::now() < deadline, "decode timed out");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  } while (!status.ended);
  std::cout << "AV1 packets=" << packets << " frames=" << status.frame_count
            << " decoder=" << status.decoder_name
            << " hardware=" << status.hardware_accelerated
            << " error=" << status.error << '\n';
  check(status.error_code == 0 && status.frame_count > 0, "no decoded frame");
  check(status.frame_count == little(bytes.data() + 24, 4),
        "fixture display frames were lost");
  if (require_hardware) {
    check(status.hardware_accelerated != 0,
          "requested hardware decoder fell back to software");
  } else {
    check(std::string(status.decoder_name) == "libdav1d" &&
              !status.hardware_accelerated,
          "AV1 did not use software libdav1d");
  }
  check(status.width == width && status.height == height,
        "unexpected dimensions");
  mc_image image{};
  check(mc_copy_rgba_scaled(decoder, 32, 32, &image) == 0, "snapshot failed");
  check(image.width > 0 && image.width <= 32 && image.height > 0 &&
            image.height <= 32,
        "snapshot ignored bounds");
  check(image.size == image.width * image.height * 4, "invalid RGBA size");
  bool colored = false;
  for (size_t index = 0; index < image.size; index += 4) {
    check(image.rgba[index + 3] == 255, "invalid alpha");
    colored |=
        image.rgba[index] || image.rgba[index + 1] || image.rgba[index + 2];
  }
  check(colored, "blank snapshot");
  mc_image_free(&image);
  mc_destroy(decoder);
  check(detached, "dispose did not detach");
}
