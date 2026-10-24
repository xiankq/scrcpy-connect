package dev.scrcpyconnect.media_codec;

import org.junit.Test;
import static org.junit.Assert.*;
import android.view.Surface;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;

/** 在 Android ART 内运行：缺失回调必须抛出异常，不能导致 JNI 中止。 */
public final class NativeCallbackContractTest {
  public static final class MissingPCM {
    public void onFrame(int width, int height) {}
  }
  public static final class Complete {
    public void onFrame(int width, int height) {}
    public long onPcm(ByteBuffer buffer) { return 0; }
    public void onPaused(boolean paused) {}
    public void onAudioClosed() {}
    public void onAudioState(ByteBuffer state) {}
    public int onHardwareDecoder(String name) { return -1; }
  }
  private long create(Object listener) throws Exception {
    Method method = MediaCodecPlugin.class.getDeclaredMethod("nativeCreate", Object.class,
        Surface.class, int.class, int.class, int.class, long.class, String.class, long.class, long.class);
    method.setAccessible(true);
    return (Long) method.invoke(null, listener, null, 100, 1, 1, 1L, null, 0L, 0L);
  }
  private void missingCallback(Object listener) throws Exception {
    try { create(listener); fail("Missing native callback accepted"); }
    catch (InvocationTargetException error) {
      assertTrue(error.getCause() instanceof IllegalStateException);
      assertTrue(error.getCause().getMessage().contains("callback signature"));
    }
  }
  @Test public void testMissingFirstCallbackDoesNotAbort() throws Exception { missingCallback(new Object()); }
  @Test public void testMissingSecondCallbackDoesNotAbort() throws Exception { missingCallback(new MissingPCM()); }
  @Test public void testValidCallbacksReachAttachValidation() throws Exception { assertEquals(0L, create(new Complete())); }
}
