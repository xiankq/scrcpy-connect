import com.genymobile.scrcpy.Options;
import com.genymobile.scrcpy.device.Streamer;
import com.genymobile.scrcpy.model.Size;
import com.genymobile.scrcpy.video.CaptureControl;
import com.genymobile.scrcpy.video.SurfaceCapture;
import com.genymobile.scrcpy.video.SurfaceEncoder;
import com.genymobile.scrcpy.video.VideoCodec;
import com.genymobile.scrcpy.video.VideoConstraints;

import android.media.MediaCodec;
import android.system.Os;
import android.view.Surface;

import java.io.FileDescriptor;
import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Runs the compiled production streamCapture(), replacing only Android APIs. */
public final class InitialCodecTest {
    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void await(CountDownLatch latch, String message) throws Exception {
        check(latch.await(2, TimeUnit.SECONDS), message);
    }

    private static final class Capture extends SurfaceCapture {
        int inits;
        int starts;
        int stops;
        int releases;
        volatile boolean closed;
        boolean failInit;
        Runnable onStop;

        @Override
        protected void init(VideoConstraints constraints) throws IOException {
            inits++;
            check(constraints.getAlignment() == 2, "real capabilities must determine capture alignment");
            if (failInit) {
                throw new IOException("fixture init failure");
            }
        }

        @Override
        public Size getSize() {
            return new Size(640, 480);
        }

        @Override
        public void start(Surface surface) {
            check(!surface.released, "capture must receive a live input surface");
            starts++;
        }

        @Override
        public void stop() {
            stops++;
            if (onStop != null) {
                onStop.run();
            }
        }

        @Override
        public boolean isClosed() {
            return closed;
        }

        @Override
        public void release() {
            releases++;
        }

        @Override
        protected boolean applyNewVideoConstraints(VideoConstraints constraints) {
            return false;
        }
    }

    private static final class Session implements AutoCloseable {
        final Capture capture = new Capture();
        final SurfaceEncoder encoder;
        final CaptureControl control;
        final AtomicReference<Throwable> failure = new AtomicReference<>();
        final Thread thread;

        Session() throws Exception {
            MediaCodec.resetFixture();
            Os.resetFixture();
            Streamer streamer = new Streamer(new FileDescriptor(), VideoCodec.H264, true, false);
            encoder = new SurfaceEncoder(capture, streamer, new Options());
            Field field = SurfaceEncoder.class.getDeclaredField("captureControl");
            field.setAccessible(true);
            control = (CaptureControl) field.get(encoder);
            Method stream = SurfaceEncoder.class.getDeclaredMethod("streamCapture");
            stream.setAccessible(true);
            thread = new Thread(() -> {
                try {
                    stream.invoke(encoder);
                } catch (InvocationTargetException error) {
                    failure.set(error.getCause());
                } catch (Throwable error) {
                    failure.set(error);
                }
            }, "actual-streamCapture-test");
            // A failed assertion must never hang the JVM test process.
            thread.setDaemon(true);
        }

        void start() {
            thread.start();
        }

        MediaCodec awaitEncoding() throws Exception {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
            while (System.nanoTime() < deadline && failure.get() == null) {
                for (MediaCodec codec : MediaCodec.created) {
                    if (codec.reading.getCount() == 0) {
                        return codec;
                    }
                }
                Thread.sleep(5);
            }
            throw new AssertionError("real encode loop did not start: " + failure.get());
        }

        void healthy() {
            check(failure.get() == null, "streamCapture failed: " + failure.get());
        }

        @Override
        public void close() throws Exception {
            capture.closed = true;
            for (MediaCodec codec : MediaCodec.created) {
                codec.emitEos = true;
            }
            control.reset(CaptureControl.RESET_REASON_TERMINATED);
            thread.join(2000);
            check(!thread.isAlive(), "streamCapture must terminate");
        }
    }

    private static void releasedResources() {
        for (MediaCodec codec : MediaCodec.created) {
            check(codec.released && codec.releaseCalls == 1, "every allocated codec must be released exactly once");
            if (codec.inputSurface != null) {
                check(codec.inputSurface.released, "pause ACK must follow input-surface release");
                check(codec.stopCalls == 1, "started codec must stop before release");
            }
        }
    }

    private static void unpausedUsesOneCodec() throws Exception {
        try (Session session = new Session()) {
            session.start();
            MediaCodec first = session.awaitEncoding();
            check(MediaCodec.created.size() == 1,
                    "initial capture must reuse the capability codec; allocations=" + MediaCodec.created.size());
            check(first == MediaCodec.created.get(0), "first allocated codec must encode");
            session.close();
            session.healthy();
            releasedResources();
            check(session.capture.releases == 1, "capture must release on normal exit");
        }
    }

    private static void initialPauseThenResume() throws Exception {
        try (Session session = new Session()) {
            CountDownLatch paused = new CountDownLatch(1);
            AtomicReference<Throwable> ackFailure = new AtomicReference<>();
            CaptureControl controllerControl = session.capture.getCaptureControl();
            check(controllerControl != null,
                    "Controller must see capture control before streamCapture starts or initial pause is dropped");
            check(controllerControl == session.control, "Controller and encoder must share the same gate");
            controllerControl.setCapturePaused(true, () -> {
                try {
                    byte[] bytes = Os.writtenBytes();
                    check(bytes.length == 4 && ByteBuffer.wrap(bytes).getInt() == VideoCodec.H264.getId(),
                            "video codec header must precede initial pause ACK");
                    check(MediaCodec.created.isEmpty(),
                            "initial pause must allocate no codec; allocations=" + MediaCodec.created.size());
                } catch (Throwable error) {
                    ackFailure.set(error);
                } finally {
                    paused.countDown();
                }
            });
            session.start();
            await(paused, "initial pause ACK missing");
            check(ackFailure.get() == null, "initial ACK contract: " + ackFailure.get());
            check(session.thread.isAlive() && session.capture.starts == 0, "initial pause must park capture");
            CountDownLatch resumed = new CountDownLatch(1);
            session.control.setCapturePaused(false, resumed::countDown);
            await(resumed, "resume ACK missing");
            session.awaitEncoding();
            check(session.capture.starts == 1 && MediaCodec.created.size() == 1, "resume must start one real capture and codec");
            session.healthy();
        }
        releasedResources();
    }

    private static void pauseDuringCreation() throws Exception {
        try (Session session = new Session()) {
            CountDownLatch paused = new CountDownLatch(1);
            AtomicReference<Throwable> ackFailure = new AtomicReference<>();
            MediaCodec.afterCreate = () -> {
                MediaCodec.afterCreate = null;
                session.control.setCapturePaused(true, () -> {
                    try {
                        releasedResources();
                        check(session.capture.starts == 1 && session.capture.stops == 1,
                                "pause after initial gate must clean up the real capture iteration");
                    } catch (Throwable error) {
                        ackFailure.set(error);
                    } finally {
                        paused.countDown();
                    }
                });
            };
            session.start();
            await(paused, "pause during codec creation must reach ACK");
            check(ackFailure.get() == null, "creation-race ACK contract: " + ackFailure.get());
            check(MediaCodec.created.size() == 1 && session.thread.isAlive(), "creation race must park after releasing one codec");
            session.control.setCapturePaused(false, () -> {});
            session.awaitEncoding();
            check(MediaCodec.created.size() == 2, "resume must allocate a new codec after pause released the first");
            session.healthy();
        }
        releasedResources();
    }

    private static void pauseDuringCleanup() throws Exception {
        try (Session session = new Session()) {
            session.start();
            session.awaitEncoding();
            CountDownLatch acknowledgements = new CountDownLatch(2);
            AtomicReference<Throwable> ackFailure = new AtomicReference<>();
            Runnable acknowledge = () -> {
                try {
                    releasedResources();
                    check(session.capture.stops == 1, "pause ACK must follow capture.stop");
                } catch (Throwable error) {
                    ackFailure.set(error);
                } finally {
                    acknowledgements.countDown();
                }
            };
            session.capture.onStop = () -> session.control.setCapturePaused(true, acknowledge);
            session.control.setCapturePaused(true, acknowledge);
            await(acknowledgements, "both pause requests must ACK after cleanup");
            check(ackFailure.get() == null, "cleanup-race ACK contract: " + ackFailure.get());
            check(session.thread.isAlive(), "cleanup pause must leave capture parked");
            session.healthy();
        }
        releasedResources();
    }

    private static void initFailureReleasesCodec() throws Exception {
        try (Session session = new Session()) {
            session.capture.failInit = true;
            session.start();
            session.thread.join(2000);
            check(!session.thread.isAlive(), "init failure must exit");
            check(session.failure.get() instanceof IOException, "init failure must propagate");
            releasedResources();
            check(MediaCodec.created.size() == 1 && session.capture.starts == 0, "init failure must allocate only the capability codec");
            check(session.capture.releases == 1, "failed capture.init must still release partially initialized capture");
        }
    }

    private interface Test {
        void run() throws Exception;
    }

    public static void main(String[] args) throws Exception {
        String[] names = {"unpausedUsesOneCodec", "initialPauseThenResume", "pauseDuringCreation", "pauseDuringCleanup", "initFailureReleasesCodec"};
        Test[] tests = {InitialCodecTest::unpausedUsesOneCodec, InitialCodecTest::initialPauseThenResume,
                InitialCodecTest::pauseDuringCreation, InitialCodecTest::pauseDuringCleanup, InitialCodecTest::initFailureReleasesCodec};
        int failures = 0;
        for (int i = 0; i < tests.length; i++) {
            try {
                tests[i].run();
                System.out.println("PASS " + names[i]);
            } catch (Throwable error) {
                failures++;
                System.err.println("FAIL " + names[i] + ": " + error);
            }
        }
        check(failures == 0, failures + " actual SurfaceEncoder lifecycle regression(s) failed");
        System.out.println("Initial codec lifecycle JVM checks passed");
    }
}
