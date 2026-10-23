//! Bounded asynchronous sample-clock compensation for remote PCM.
//! The system output's pending frames are feedback, not wall-clock playback.

pub struct Regulator {
    average: f64,
    integral: f64,
    phase: f64,
    previous: [i16; 2],
    initialized: bool,
    generation: Option<u64>,
    output: Vec<u8>,
}
impl Default for Regulator {
    fn default() -> Self {
        Self {
            average: 960.0,
            integral: 0.0,
            phase: 0.0,
            previous: [0; 2],
            initialized: false,
            generation: None,
            output: Vec::new(),
        }
    }
}
impl Regulator {
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    // A small PI controller slowly adjusts the sample rate to maintain 20ms
    // of device audio. Smoothing rejects packet jitter; compensation is bounded
    // to 0.5%, with no unbounded FIFO or abrupt whole-packet tail discard.
    fn rate(&mut self, queued: u64, generation: u64) -> f64 {
        if self.generation != Some(generation) {
            self.reset();
            self.generation = Some(generation);
        }
        self.average += (queued as f64 - self.average) / 128.0;
        let error = (self.average - 960.0) / 48_000.0;
        self.integral = (self.integral + error * 0.0002).clamp(-0.003, 0.003);
        (1.0 + error * 0.08 + self.integral).clamp(0.995, 1.005)
    }

    pub fn process(&mut self, input: &[u8], queued: u64, generation: u64) -> &[u8] {
        let rate = self.rate(queued, generation);
        self.output.clear();
        let frames = input.len() / 4;
        if frames == 0 {
            return &self.output;
        }
        let sample = |index: usize| -> [i16; 2] {
            let offset = index * 4;
            [
                i16::from_le_bytes([input[offset], input[offset + 1]]),
                i16::from_le_bytes([input[offset + 2], input[offset + 3]]),
            ]
        };
        if !self.initialized {
            self.previous = sample(0);
            self.initialized = true;
        }
        self.output.reserve((frames + frames / 100 + 2) * 4);
        while self.phase < frames as f64 {
            let index = self.phase.floor() as usize;
            let fraction = self.phase - index as f64;
            let left = if index == 0 {
                self.previous
            } else {
                sample(index - 1)
            };
            let right = sample(index);
            for channel in 0..2 {
                let value = left[channel] as f64
                    + (right[channel] as f64 - left[channel] as f64) * fraction;
                self.output.extend_from_slice(
                    &(value.round().clamp(-32768.0, 32767.0) as i16).to_le_bytes(),
                );
            }
            self.phase += rate;
        }
        self.phase -= frames as f64;
        self.previous = sample(frames - 1);
        &self.output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opposite_device_clock_drifts_remain_bounded_for_thirty_minutes() {
        for drift in [-0.001, 0.001] {
            let mut regulator = Regulator::default();
            let mut queue = 960.0_f64;
            let mut min = f64::MAX;
            let mut max = 0.0_f64;
            for _ in 0..84_375 {
                // 30 minutes of 1024-frame PCM packets.
                let rate = regulator.rate(queue.max(0.0).round() as u64, 1);
                queue += 1024.0 / rate - 1024.0 * (1.0 + drift);
                min = min.min(queue);
                max = max.max(queue);
            }
            assert!(
                min > 0.0 && max < 2400.0,
                "unbounded drift {drift}: {min}..{max}"
            );
        }
    }

    #[test]
    fn packet_boundaries_preserve_stereo_constant_samples_and_fractional_rate() {
        let frame = [1234_i16.to_le_bytes(), (-2345_i16).to_le_bytes()].concat();
        let input = frame.repeat(1024);
        let mut regulator = Regulator::default();
        let mut frames = 0;
        for _ in 0..1000 {
            let output = regulator.process(&input, 1200, 7);
            assert!(output
                .as_chunks::<4>()
                .0
                .iter()
                .all(|sample| sample.as_slice() == frame.as_slice()));
            frames += output.len() / 4;
        }
        assert!(frames < 1_024_000 && frames > 1_018_000);
        assert!(!regulator.process(&input, 960, 8).is_empty());
    }
}
