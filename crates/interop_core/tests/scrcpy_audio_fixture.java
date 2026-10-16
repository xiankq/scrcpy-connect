// Test-only tone source, launched as shell through app_process; no APK or root.
// Compile against android.jar, dex with d8, then set INTEROP_AUDIO_FIXTURE to its JAR.
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;

class InteropAudioFixture {
    public static void main(String[] args) throws Exception {
        final int rate = 48000;
        final int channels = AudioFormat.CHANNEL_OUT_STEREO;
        AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setSampleRate(rate).setChannelMask(channels)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(Math.max(8192,
                        AudioTrack.getMinBufferSize(rate, channels, AudioFormat.ENCODING_PCM_16BIT)))
                .setTransferMode(AudioTrack.MODE_STREAM).build();
        try {
            if (track.getState() != AudioTrack.STATE_INITIALIZED) {
                throw new IllegalStateException("AudioTrack not initialized");
            }
            short[] block = new short[960 * 2];
            track.play();
            for (int offset = 0; offset < rate * 3; offset += 960) {
                for (int i = 0; i < 960; ++i) {
                    short sample = (short) (4096 * Math.sin(2 * Math.PI * 880 * (offset + i) / rate));
                    block[i * 2] = sample;
                    block[i * 2 + 1] = sample;
                }
                int written = 0;
                while (written < block.length) {
                    int count = track.write(block, written, block.length - written,
                            AudioTrack.WRITE_BLOCKING);
                    if (count <= 0) throw new IllegalStateException("AudioTrack write: " + count);
                    written += count;
                }
            }
            while (Integer.toUnsignedLong(track.getPlaybackHeadPosition()) < rate * 3) {
                Thread.sleep(10);
            }
            System.out.println("fixture: 144000 frames at 880Hz played");
        } finally {
            track.stop();
            track.release();
        }
        // app_process has framework binder/audio threads after constructing an
        // AudioTrack. Terminate this test-owned VM once playback has completed.
        System.exit(0);
    }
}
