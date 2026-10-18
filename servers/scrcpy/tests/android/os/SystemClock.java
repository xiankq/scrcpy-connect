package android.os;

/** Monotonic time for the actual resize debouncer's JVM thread. */
public final class SystemClock {
    public static long uptimeMillis() {
        return System.nanoTime() / 1_000_000;
    }
}
