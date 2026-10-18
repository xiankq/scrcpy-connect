package android.media;

/** Minimal JVM stand-in: verifies that requests interrupt a running encoder. */
public final class MediaCodec {
    public int eosRequests;
    public static final int BUFFER_FLAG_END_OF_STREAM = 4;
    public static final int BUFFER_FLAG_CODEC_CONFIG = 2;
    public final java.util.concurrent.CountDownLatch reading = new java.util.concurrent.CountDownLatch(1);
    public volatile boolean emitEos;
    public volatile long lastTimeoutUs;

    public static final class BufferInfo {
        public int flags;
        public int size;
        public long presentationTimeUs;
    }

    // Deliberately do not produce EOS on signalEndOfInputStream. A pending
    // capture request must still release the actual encode loop promptly.
    public int dequeueOutputBuffer(BufferInfo info, long timeoutUs) {
        lastTimeoutUs = timeoutUs;
        reading.countDown();
        try {
            Thread.sleep(timeoutUs < 0 ? 1000 : Math.min(100, timeoutUs / 1000));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        info.flags = emitEos ? BUFFER_FLAG_END_OF_STREAM : 0;
        info.size = 0;
        return -1;
    }

    public java.nio.ByteBuffer getOutputBuffer(int index) {
        throw new AssertionError("this fixture produces no output buffer");
    }

    public void releaseOutputBuffer(int index, boolean render) {
        throw new AssertionError("this fixture produces no output buffer");
    }

    public void signalEndOfInputStream() {
        eosRequests++;
    }
}
