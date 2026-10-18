import com.genymobile.scrcpy.Options;
import com.genymobile.scrcpy.display.DisplayResizeDebouncer;
import com.genymobile.scrcpy.model.Size;
import com.genymobile.scrcpy.video.CaptureControl;
import com.genymobile.scrcpy.video.NewDisplayCapture;
import com.genymobile.scrcpy.video.VideoConstraints;

import java.lang.reflect.Field;

/** Exercises the actual flex-display resize entry point before capture init. */
public final class NewDisplayInitialResizeTest {
    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static Object field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    public static void main(String[] args) throws Exception {
        Options options = Options.parse("5.0.1", "new_display=1280x960/160", "flex_display=true");
        NewDisplayCapture capture = new NewDisplayCapture(null, options);
        Thread debounceThread = null;
        try {
            // The controller can receive multiple resizes while initial pause
            // keeps the encoder parked before real constraints are available.
            capture.requestResize(405, 307);
            capture.requestResize(1919, 543);
            check(field(capture, "debouncer") == null, "early resize must not start capture resources");

            capture.init(new CaptureControl(), new VideoConstraints(1000, 16, null));
            Size displaySize = (Size) field(capture, "displaySize");
            check(displaySize.equals(new Size(992, 528)),
                    "latest early resize must be constrained at actual init; actual=" + displaySize);

            DisplayResizeDebouncer debouncer = (DisplayResizeDebouncer) field(capture, "debouncer");
            check(debouncer != null, "real init must create the resize debouncer");
            debounceThread = (Thread) field(debouncer, "thread");
            check(debounceThread != null && debounceThread.isAlive(), "real init must start the debouncer");
        } finally {
            capture.release();
            if (debounceThread != null) {
                debounceThread.join(2000);
                check(!debounceThread.isAlive(), "capture.release must stop its debouncer thread");
            }
        }
        System.out.println("New display initial resize JVM checks passed");
    }
}
