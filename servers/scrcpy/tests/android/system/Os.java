package android.system;

import java.io.ByteArrayOutputStream;
import java.io.FileDescriptor;
import java.nio.ByteBuffer;

/** Keeps the real Streamer and IO implementations observable without a device. */
public final class Os {
    private static final ByteArrayOutputStream OUTPUT = new ByteArrayOutputStream();

    public static synchronized void resetFixture() {
        OUTPUT.reset();
    }

    public static synchronized byte[] writtenBytes() {
        return OUTPUT.toByteArray();
    }

    public static synchronized int write(FileDescriptor fd, ByteBuffer buffer) throws ErrnoException {
        int size = buffer.remaining();
        byte[] bytes = new byte[size];
        buffer.get(bytes);
        OUTPUT.write(bytes, 0, size);
        return size;
    }
}
