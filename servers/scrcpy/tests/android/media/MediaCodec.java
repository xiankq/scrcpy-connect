package android.media;

/** Minimal JVM stand-in: verifies that requests interrupt a running encoder. */
public final class MediaCodec {
    public int eosRequests;

    public void signalEndOfInputStream() {
        eosRequests++;
    }
}
