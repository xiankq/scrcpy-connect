import com.genymobile.scrcpy.control.ControlMessage;
import com.genymobile.scrcpy.control.ControlMessageReader;
import com.genymobile.scrcpy.control.ControlProtocolException;
import com.genymobile.scrcpy.video.CaptureControl;

import android.media.MediaCodec;

import java.io.ByteArrayInputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public final class CapturePauseTest {
    private static void check(boolean value, String message) {
        if (!value) {
            throw new AssertionError(message);
        }
    }

    private static Thread enterGate(CaptureControl control, AtomicBoolean result) {
        Thread thread = new Thread(() -> result.set(control.awaitCaptureEnabled()));
        thread.start();
        return thread;
    }

    private static void pausedGateThenResume() throws Exception {
        CaptureControl control = new CaptureControl();
        MediaCodec codec = new MediaCodec();
        control.setRunningMediaCodec(codec);
        CountDownLatch paused = new CountDownLatch(1);
        control.setCapturePaused(true, paused::countDown);
        check(codec.eosRequests == 1, "pause must request EOS");
        check(paused.getCount() == 1, "controller must not ACK before the encoder reaches its gate");
        // SurfaceEncoder calls the gate only after capture/codec/input-surface cleanup.
        control.setRunningMediaCodec(null);
        AtomicBoolean result = new AtomicBoolean();
        Thread encoder = enterGate(control, result);
        check(paused.await(2, TimeUnit.SECONDS), "pause must ACK at the gate");
        check(encoder.isAlive(), "encoder must stay parked after pause ACK");
        control.reset(CaptureControl.RESET_REASON_DISPLAY_PROPERTIES_CHANGED);
        check(encoder.isAlive(), "a display reset must not reopen the pause gate");
        CountDownLatch resumed = new CountDownLatch(1);
        control.setCapturePaused(false, resumed::countDown);
        check(resumed.await(2, TimeUnit.SECONDS), "resume must ACK when opening the gate");
        encoder.join(2000);
        check(!encoder.isAlive() && result.get(), "resume must let the encoder proceed");
        int reasons = control.consumeReset();
        check((reasons & CaptureControl.RESET_REASON_DISPLAY_PROPERTIES_CHANGED) != 0,
                "display changes while paused must survive until the next encoder session");
    }

    private static void terminationWakesGate() throws Exception {
        CaptureControl control = new CaptureControl();
        CountDownLatch paused = new CountDownLatch(1);
        control.setCapturePaused(true, paused::countDown);
        AtomicBoolean result = new AtomicBoolean(true);
        Thread encoder = enterGate(control, result);
        check(paused.await(2, TimeUnit.SECONDS), "pause ACK missing");
        control.reset(CaptureControl.RESET_REASON_TERMINATED);
        encoder.join(2000);
        check(!encoder.isAlive() && !result.get(), "termination must wake a paused gate without restarting capture");
        AtomicBoolean staleAck = new AtomicBoolean();
        control.setCapturePaused(false, () -> staleAck.set(true));
        check(!control.awaitCaptureEnabled() && !staleAck.get(), "terminated capture must never ACK late requests");
    }

    private static void queuedRequestsStayOrdered() throws Exception {
        CaptureControl control = new CaptureControl();
        StringBuilder order = new StringBuilder();
        control.setCapturePaused(true, () -> order.append('P'));
        control.setCapturePaused(false, () -> order.append('R'));
        check(control.awaitCaptureEnabled(), "a queued resume must open the gate");
        check(order.toString().equals("PR"), "capture ACKs must preserve command order");
    }

    private static ControlMessage read(long sequence, int value) throws Exception {
        byte[] bytes = ByteBuffer.allocate(10).put((byte) 128).putLong(sequence).put((byte) value).array();
        return new ControlMessageReader(new ByteArrayInputStream(bytes)).read();
    }

    private static void wireProtocol() throws Exception {
        long sequence = 0xfedcba9876543210L;
        ControlMessage paused = read(sequence, 1);
        check(paused.getType() == 128 && paused.getSequence() == sequence && paused.getOn(), "pause wire fields changed");
        check(!read(1, 0).getOn(), "resume byte must be accepted");
        for (int value : new int[] {2, 255}) {
            try {
                read(1, value);
                throw new AssertionError("invalid boolean accepted");
            } catch (ControlProtocolException expected) {
                // Expected: reject malformed peers before the capture gate.
            }
        }
        try {
            read(0, 1);
            throw new AssertionError("sequence zero accepted");
        } catch (ControlProtocolException expected) {
            // Sequence zero is reserved by the upstream protocol.
        }
    }

    public static void main(String[] args) throws Exception {
        wireProtocol();
        pausedGateThenResume();
        terminationWakesGate();
        queuedRequestsStayOrdered();
        System.out.println("Capture pause protocol/gate JVM checks passed");
    }
}
