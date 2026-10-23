#include "../audio.h"
#include <array>
#include <cassert>
#include <cstdio>
int main() {
  mc_linux::Audio audio;
  assert(audio.ready());
  std::array<uint8_t, 1920> samples{};
  assert(audio.write(samples.data(), samples.size()) ==
         int64_t(samples.size()));
  mc_audio_state playing{};
  assert(audio.state(&playing) == 0);
  assert(playing.played_frames + playing.queued_frames == samples.size() / 4);
  audio.pause(true);
  assert(audio.write(samples.data(), samples.size()) == 0);
  mc_audio_state paused{};
  assert(audio.state(&paused) == 0);
  assert(!paused.running && !paused.queued_frames);
  assert(paused.generation > playing.generation);
  audio.pause(false);
  assert(audio.write(samples.data(), samples.size()) ==
         int64_t(samples.size()));
  mc_audio_state resumed{};
  assert(audio.state(&resumed) == 0);
  assert(resumed.generation > paused.generation);
  assert(resumed.played_frames + resumed.queued_frames == samples.size() / 4);
  puts("PASS: ALSA accepted-byte accounting, pause drop/prepare, device clock "
       "generations");
}
