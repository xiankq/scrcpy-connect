// 仅用于测试的 SinkV1 生产者，不链接到交付插件。
#include "../media_codec.h"
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

namespace {
std::mutex lifecycle;
std::thread worker;
std::atomic<bool> stopping{false};
uint32_t little32(const uint8_t *p) {
  return p[0] | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) |
         (uint32_t(p[3]) << 24);
}
} // namespace

extern "C" MC_EXPORT int32_t replay_detach(const uint8_t *, size_t, uint64_t) {
  std::lock_guard<std::mutex> lock(lifecycle);
  stopping = true;
  if (worker.joinable())
    worker.join();
  return 0;
}

extern "C" MC_EXPORT int32_t replay_attach(const uint8_t *, size_t,
                                           uint64_t generation,
                                           const mc_sink_v1 *value) {
  std::lock_guard<std::mutex> lock(lifecycle);
  if (!value || value->abi_version != 1 ||
      value->struct_size < sizeof(mc_sink_v1) || !value->event ||
      worker.joinable())
    return -1;
  char path[32768];
  size_t path_length = 0;
  if (getenv_s(&path_length, path, sizeof(path),
               "MEDIA_CODEC_REPLAY_FIXTURE") != 0 ||
      path_length <= 1)
    return -2;
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  const auto size = stream.tellg();
  if (size < 32 || size > 64 * 1024 * 1024)
    return -3;
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  stream.seekg(0);
  if (!stream.read(reinterpret_cast<char *>(bytes.data()), size) ||
      little32(bytes.data()) != 0x46494b44 ||
      little32(bytes.data() + 8) != 0x31305641)
    return -3;
  const uint32_t width = bytes[12] | (uint32_t(bytes[13]) << 8);
  const uint32_t height = bytes[14] | (uint32_t(bytes[15]) << 8);
  if (!width || !height)
    return -3;
  auto sink = *value;
  stopping = false;
  worker = std::thread([sink, generation, width, height,
                        bytes = std::move(bytes)] {
    auto send = [&](uint32_t kind, const uint8_t *data, size_t length,
                    int64_t pts, uint32_t flags) {
      int32_t result;
      do {
        if (stopping)
          return int32_t(-1);
        result = sink.event(sink.context, kind, generation, 3, width, height,
                            data, length, pts, flags);
        if (result == 1)
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
      } while (result == 1);
      return result;
    };
    if (send(1, nullptr, 0, 0, 0) != 0)
      return;
    size_t position = 32;
    int64_t pts = 0;
    while (position + 12 <= bytes.size() && !stopping) {
      const auto length = little32(bytes.data() + position);
      position += 12;
      if (length > 8 * 1024 * 1024 || length > bytes.size() - position ||
          send(2, bytes.data() + position, length, pts, pts == 0 ? 1 : 0) != 0)
        return;
      pts += 16667;
      position += length;
      std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
  });
  return 0;
}
