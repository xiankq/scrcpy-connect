package android.util;

/** Suppress Android logging while real Ln still reports failures to stderr. */
public final class Log {
    public static int e(String tag, String message, Throwable error) {
        return 0;
    }
}
