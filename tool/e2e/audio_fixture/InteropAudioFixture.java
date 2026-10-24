// 测试专用音调源，通过 app_process 以 shell 启动，无需 APK 或 root。
// 使用 android.jar 编译并用 d8 转 dex，再将 INTEROP_AUDIO_FIXTURE 设为其 JAR。
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
        // app_process 构造 AudioTrack 后存在 framework Binder 和音频线程；
        // 播放完成后终止本测试拥有的 VM。
        System.exit(0);
    }
}
