#ifndef MEDIA_CODEC_LINUX_AUDIO_H
#define MEDIA_CODEC_LINUX_AUDIO_H
#include "../native/media_codec.h"
#include <algorithm>
#include <chrono>
#include <dlfcn.h>
#include <mutex>
namespace mc_linux {
class Audio {
public:
  Audio() {
    library_ = dlopen("libasound.so.2", RTLD_NOW | RTLD_LOCAL);
    if (!library_)
      return;
    open_ = symbol<Open>("snd_pcm_open");
    params_ = symbol<Params>("snd_pcm_set_params");
    write_ = symbol<Write>("snd_pcm_writei");
    recover_ = symbol<Recover>("snd_pcm_recover");
    wait_ = symbol<Wait>("snd_pcm_wait");
    close_ = symbol<Close>("snd_pcm_close");
    drop_ = symbol<Close>("snd_pcm_drop");
    prepare_ = symbol<Close>("snd_pcm_prepare");
    delay_ = symbol<Delay>("snd_pcm_delay");
    state_ = symbol<State>("snd_pcm_state");
    if (open_ && params_ && write_ && recover_ && wait_ && close_ && drop_ &&
        prepare_ && delay_ && state_)
      reopen();
  }
  ~Audio() {
    shutdown();
    if (library_)
      dlclose(library_);
  }
  void shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (pcm_) {
      drop_(pcm_);
      close_(pcm_);
      pcm_ = nullptr;
    }
  }
  bool ready() const { return pcm_ != nullptr; }
  void pause(bool value) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (paused_ == value)
      return;
    paused_ = value;
    if (pcm_) {
      // 同时清空设备队列；只停止 Rust 写入会使播放时钟标为暂停后仍可听到排队声音。
      drop_(pcm_);
      if (!value && prepare_(pcm_) < 0)
        reopen();
    }
    submitted_ = 0;
    ++generation_;
  }
  int state(mc_audio_state *result) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pcm_)
      return -1;
    long queued = 0;
    if (delay_(pcm_, &queued) < 0)
      queued = 0;
    result->queued_frames =
        std::min<uint64_t>(submitted_, std::max<long>(0, queued));
    result->played_frames = submitted_ - result->queued_frames;
    result->generation = generation_;
    result->running = !paused_ && state_(pcm_) == 3; // SND_PCM_STATE_RUNNING
    return 0;
  }
  int64_t write(const uint8_t *bytes, size_t length) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (paused_)
      return 0;
    if (!pcm_ && !reopen())
      return -1;
    size_t frames = length / 4, original = frames;
    auto deadline =
        std::chrono::steady_clock::now() + std::chrono::milliseconds(80);
    while (frames && std::chrono::steady_clock::now() < deadline) {
      long count = write_(pcm_, bytes, frames);
      if (count > 0) {
        bytes += count * 4;
        frames -= count;
        submitted_ += count;
      } else if (count == -11 || count == 0) {
        wait_(pcm_, 5);
      } else {
        int recovered = recover_(pcm_, static_cast<int>(count), 1);
        if (recovered < 0) {
          // 默认路由或设备移除可能使 PCM 永久失效；此处仅重开一次，Rust 保留未写入尾部以供重试。
          reopen();
          return original == frames ? -1 : int64_t((original - frames) * 4);
        }
        submitted_ = 0;
        ++generation_;
      }
    }
    return static_cast<int64_t>((original - frames) * 4);
  }

private:
  bool reopen() {
    if (pcm_) {
      drop_(pcm_);
      close_(pcm_);
      pcm_ = nullptr;
    }
    if (open_(&pcm_, "default", 0, 1) < 0) {
      pcm_ = nullptr;
      return false;
    }
    if (params_(pcm_, 2, 3, 2, 48000, 1, 20000) < 0) {
      close_(pcm_);
      pcm_ = nullptr;
      return false;
    }
    submitted_ = 0;
    ++generation_;
    return true;
  }
  template <class T> T symbol(const char *name) {
    return reinterpret_cast<T>(dlsym(library_, name));
  }
  using Open = int (*)(void **, const char *, int, int);
  using Params = int (*)(void *, int, int, unsigned, unsigned, int, unsigned);
  using Write = long (*)(void *, const void *, unsigned long);
  using Recover = int (*)(void *, int, int);
  using Wait = int (*)(void *, int);
  using Close = int (*)(void *);
  using Delay = int (*)(void *, long *);
  using State = int (*)(void *);
  void *library_ = nullptr, *pcm_ = nullptr;
  Open open_ = nullptr;
  Params params_ = nullptr;
  Write write_ = nullptr;
  Recover recover_ = nullptr;
  Wait wait_ = nullptr;
  Close close_ = nullptr, drop_ = nullptr, prepare_ = nullptr;
  Delay delay_ = nullptr;
  State state_ = nullptr;
  std::mutex mutex_;
  bool paused_ = false;
  uint64_t submitted_ = 0, generation_ = 0;
};
} // namespace mc_linux
#endif
