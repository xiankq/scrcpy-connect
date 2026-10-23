// Exercise the production WASAPI sink on its owning thread. Silence verifies
// device acceptance and clock state without claiming acoustic output.
#include "../media_codec_plugin.cpp"
#include <array>
#include <cassert>
#include <cstdio>
#include <thread>

int main() {
  Audio audio;
  std::array<uint8_t, 5760> samples{};
  assert(audio.write(samples.data(), samples.size()) ==
         static_cast<int64_t>(samples.size()));
  mc_audio_state playing{};
  assert(audio.state(&playing) == 0);
  assert(playing.running && playing.played_frames <= samples.size() / 4);
  assert(playing.queued_frames <= samples.size() / 4);
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  mc_audio_state drained{};
  assert(audio.state(&drained) == 0);
  assert(drained.played_frames > 0 && !drained.queued_frames);
  audio.pause(true);
  assert(audio.write(samples.data(), samples.size()) == 0);
  mc_audio_state paused{};
  assert(audio.state(&paused) == 0);
  assert(!paused.running && !paused.queued_frames);
  assert(paused.generation > playing.generation);
  audio.pause(false);
  assert(audio.write(samples.data(), samples.size()) ==
         static_cast<int64_t>(samples.size()));
  mc_audio_state resumed{};
  assert(audio.state(&resumed) == 0);
  assert(resumed.running && resumed.generation > paused.generation);
  audio.shutdown();
  assert(audio.state(&resumed) < 0);
  audio.shutdown();
  puts("PASS: WASAPI event writes, device clock, pause/reset/resume, worker "
       "close");
}
