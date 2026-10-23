package dev.scrcpyconnect.media_codec;

import android.graphics.Canvas;
import android.graphics.PixelFormat;
import android.media.ImageReader;
import android.os.Build;
import android.view.Surface;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.junit.Assume.*;

/** Exercise consumer abandonment concurrently with a live CPU producer. */
public final class SurfaceConsumerLifecycleTest {
  @Test public void abandoningConsumerStopsSoftwareProducer() throws Exception {
    assumeTrue(Build.VERSION.SDK_INT >= 26);
    ImageReader consumer = ImageReader.newInstance(16, 16, PixelFormat.RGBA_8888, 1);
    Surface producer = consumer.getSurface();
    AtomicInteger posted = new AtomicInteger();
    CountDownLatch done = new CountDownLatch(1);
    Thread writer = new Thread(() -> {
      try {
        for (int frame = 0; frame < 100000; ++frame) {
          Canvas canvas = producer.lockCanvas(null);
          canvas.drawColor(0xffff0000);
          producer.unlockCanvasAndPost(canvas); posted.incrementAndGet();
        }
      } catch (RuntimeException abandoned) {
        // A removed consumer rejects a pending/future dequeue.
      } finally { done.countDown(); }
    });
    writer.start();
    try {
      long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
      while (posted.get() == 0 && System.nanoTime() < deadline) Thread.sleep(5);
      assertTrue("CPU producer did not post its first buffer", posted.get() > 0);
      assertFalse("CPU producer stopped before consumer removal", done.await(20, TimeUnit.MILLISECONDS));
      consumer.close();
      assertTrue("Abandoning consumer did not stop CPU producer", done.await(2, TimeUnit.SECONDS));
    } finally {
      consumer.close(); writer.join(2000);
      if (!writer.isAlive()) producer.release();
    }
  }
}
