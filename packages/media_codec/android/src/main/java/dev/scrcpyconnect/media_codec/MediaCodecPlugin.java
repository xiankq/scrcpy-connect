package dev.scrcpyconnect.media_codec;

import android.graphics.Bitmap;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.Surface;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

/** Platform texture and PCM output; packet ownership and decoding live in the shared core. */
public final class MediaCodecPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  static { System.loadLibrary("media_codec_plugin"); }
  private final Handler main = new Handler(Looper.getMainLooper());
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private final Map<Long, Session> sessions = new ConcurrentHashMap<>();
  private final AtomicLong ids = new AtomicLong(1);
  private TextureRegistry textures;
  private MethodChannel channel;

  @Override public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    textures = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), "media_codec");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    List<Session> outputs = new ArrayList<>(sessions.values());
    for (Session session : outputs) { session.disposed = true; session.releaseTexture(); }
    // Flutter destroys texture consumers after detach returns. Also drain any
    // earlier dispose already removed from sessions. Consumers were abandoned
    // first so a blocked software dequeue cannot hold this drain indefinitely.
    Future<?> drain = worker.submit(() -> {
      for (Session session : outputs) session.closeNative();
    });
    boolean interrupted = false;
    for (;;) {
      try { drain.get(); break; }
      catch (InterruptedException error) { interrupted = true; }
      catch (ExecutionException error) { throw new IllegalStateException("Unable to drain native media", error.getCause()); }
    }
    for (Session session : outputs) session.releasePlatform();
    sessions.clear(); worker.shutdown();
    if (interrupted) Thread.currentThread().interrupt();
  }

  private static long number(Map<?, ?> args, String name, long fallback) {
    Object value = args.get(name);
    return value instanceof Number ? ((Number) value).longValue() : fallback;
  }
  private static int codec(Object value) {
    if (value instanceof Number) return ((Number) value).intValue();
    if ("h264".equals(value)) return 1;
    if ("h265".equals(value) || "hevc".equals(value)) return 2;
    if ("av1".equals(value)) return 3;
    if ("vp8".equals(value)) return 4;
    if ("vp9".equals(value)) return 5;
    return 100;
  }

  @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    Map<?, ?> args = call.arguments instanceof Map ? (Map<?, ?>) call.arguments : new HashMap<>();
    if (call.method.equals("createVideo") || call.method.equals("createAudio")) {
      Session session;
      try {
        session = new Session(ids.getAndIncrement(), args, call.method.equals("createAudio"));
      } catch (RuntimeException error) {
        result.error("media_codec_create", error.getMessage(), null);
        return;
      }
      sessions.put(session.id, session);
      worker.execute(() -> {
        try {
          session.open();
          Map<String, Object> value = new HashMap<>();
          value.put("handle", session.id);
          value.put("textureId", session.textureId());
          value.put("width", session.width);
          value.put("height", session.height);
          value.putAll(nativeBindings(session.decoder));
          main.post(() -> result.success(value));
        } catch (RuntimeException error) {
          session.closeNative();
          sessions.remove(session.id);
          main.post(() -> {
            session.releasePlatform();
            result.error("media_codec_create", error.getMessage(), null);
          });
        }
      });
      return;
    }
    Session session = sessions.get(number(args, "handle", 0));
    if (session == null) {
      if (call.method.equals("dispose")) result.success(null);
      else result.error("media_codec_handle", "Media output is no longer available", null);
      return;
    }
    if (call.method.equals("dispose")) { dispose(session, result); return; }
    if (call.method.equals("snapshot")) { snapshot(session, args, result); return; }
    worker.execute(() -> {
      try {
        Object value = null;
        switch (call.method) {
          case "status": value = nativeStatus(session.decoder); break;
          case "setPaused":
            nativeSetPaused(session.decoder, Boolean.TRUE.equals(args.get("paused")));
            break;
          case "setVolume":
            Object volume = args.get("volume");
            nativeSetVolume(session.decoder, volume instanceof Number ? ((Number) volume).doubleValue() : 1.0);
            break;
          default: main.post(result::notImplemented); return;
        }
        Object response = value;
        main.post(() -> result.success(response));
      } catch (RuntimeException error) {
        main.post(() -> result.error("media_codec_operation", error.getMessage(), null));
      }
    });
  }

  private void dispose(Session session, MethodChannel.Result result) {
    sessions.remove(session.id);
    session.disposed = true;
    session.releaseTexture();
    worker.execute(() -> {
      session.closeNative(); // Consumers are abandoned before a possibly blocked software dequeue is joined.
      main.post(() -> {
        session.releasePlatform();
        if (result != null) result.success(null);
      });
    });
  }

  private void snapshot(Session session, Map<?, ?> args, MethodChannel.Result result) {
    int maxWidth = Math.max(1, Math.min(4096, (int) number(args, "width", session.width)));
    int maxHeight = Math.max(1, Math.min(4096, (int) number(args, "height", session.height)));
    worker.execute(() -> {
      Map<String, Object> image = nativeSnapshot(session.decoder, maxWidth, maxHeight);
      main.post(() -> {
        if (image != null) { result.success(image); return; }
        if (session.textureId() < 0 || session.disposed || Build.VERSION.SDK_INT < 24) {
          result.success(null); return;
        }
        // MediaCodec Surface buffers intentionally never travel through CPU memory during playback.
        // An explicit snapshot is the only path that reads the Android Surface back.
        double scale = Math.min(1.0, Math.min((double) maxWidth / session.width, (double) maxHeight / session.height));
        Bitmap bitmap = Bitmap.createBitmap(Math.max(1, (int) (session.width * scale)),
            Math.max(1, (int) (session.height * scale)), Bitmap.Config.ARGB_8888);
        try {
          PixelCopy.request(session.surface, bitmap, status -> {
            if (status != PixelCopy.SUCCESS || session.disposed) {
              bitmap.recycle(); result.success(null); return;
            }
            worker.execute(() -> {
              int[] pixels = new int[bitmap.getWidth() * bitmap.getHeight()];
              bitmap.getPixels(pixels, 0, bitmap.getWidth(), 0, 0, bitmap.getWidth(), bitmap.getHeight());
              byte[] rgba = new byte[pixels.length * 4];
              for (int i = 0; i < pixels.length; ++i) {
                rgba[i * 4] = (byte) (pixels[i] >>> 16);
                rgba[i * 4 + 1] = (byte) (pixels[i] >>> 8);
                rgba[i * 4 + 2] = (byte) pixels[i];
                rgba[i * 4 + 3] = (byte) (pixels[i] >>> 24);
              }
              Map<String, Object> value = new HashMap<>();
              value.put("width", bitmap.getWidth()); value.put("height", bitmap.getHeight());
              value.put("rgba", rgba); bitmap.recycle();
              main.post(() -> result.success(value));
            });
          }, main);
        } catch (RuntimeException error) { bitmap.recycle(); result.success(null); }
      });
    });
  }

  private final class Session {
    final long id;
    final Map<?, ?> config;
    final TextureRegistry.SurfaceProducer producer;
    final TextureRegistry.SurfaceTextureEntry surfaceTexture;
    final Object decoderLock = new Object();
    final Object audioLock = new Object();
    AudioTrack audio;
    volatile boolean disposed;
    boolean platformReleased;
    boolean textureReleased;
    volatile boolean paused;
    volatile int width;
    volatile int height;
    volatile Surface surface;
    long decoder;
    long audioFramesWritten;
    long audioGeneration;
    long lastPlaybackHead;
    long playbackWrap;

    Session(long id, Map<?, ?> config, boolean isAudio) {
      this.id = id; this.config = config;
      width = Math.max(1, (int) number(config, "width", 1));
      height = Math.max(1, (int) number(config, "height", 1));
      if (isAudio) {
        producer = null; surfaceTexture = null;
        int minimum = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        {
          AudioTrack.Builder builder = new AudioTrack.Builder()
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(new AudioFormat.Builder().setSampleRate(48000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(Math.max(minimum, 7680));
          if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY);
          audio = builder.build();
        }
        if (audio.getState() != AudioTrack.STATE_INITIALIZED) {
          audio.release(); throw new IllegalStateException("PCM audio output is unavailable");
        }
        audio.play();
      } else {
        audio = null;
        TextureRegistry.SurfaceProducer candidate = textures.createSurfaceProducer();
        // ImageReader producers cannot apply codec crop/rotation on all engines.
        // Flutter's SurfaceTexture consumer applies the producer transform matrix.
        if (candidate.handlesCropAndRotation()) {
          producer = candidate; surfaceTexture = null;
          producer.setSize(width, height);
          surface = producer.getSurface();
          producer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
            @Override public void onSurfaceCleanup() {
              // The callback is a barrier: Flutter destroys its consumer as soon
              // as this returns. Merely posting to the worker races that release.
              synchronized (decoderLock) {
                if (decoder != 0) nativeSetSurface(decoder, null);
                surface = null;
              }
            }
            @Override public void onSurfaceAvailable() {
              synchronized (decoderLock) {
                surface = producer.getSurface();
                if (!disposed && decoder != 0) nativeSetSurface(decoder, surface);
              }
            }
          });
        } else {
          candidate.release(); producer = null;
          surfaceTexture = textures.createSurfaceTexture();
          surfaceTexture.surfaceTexture().setDefaultBufferSize(width, height);
          surface = new Surface(surfaceTexture.surfaceTexture());
        }
      }
    }

    long textureId() {
      return producer != null ? producer.id() : surfaceTexture != null ? surfaceTexture.id() : -1L;
    }
    void open() {
      synchronized (decoderLock) {
        if (disposed || decoder != 0) return;
        decoder = nativeCreate(this, surface, audio != null ? 100 : codec(config.get("codec")),
            width, height, number(config, "generation", 0), (String) config.get("sourceId"),
            number(config, "attachAddress", 0), number(config, "detachAddress", 0));
        if (decoder == 0) throw new IllegalStateException("Unable to attach native media output");
        if (paused) nativeSetPaused(decoder, true);
      }
    }
    void closeNative() {
      synchronized (decoderLock) {
        if (decoder != 0) { nativeDispose(decoder); decoder = 0; }
      }
    }
    // Called on the main thread. Native workers retain their ANativeWindow, so
    // abandoning the consumer is safe and unblocks an in-flight software lock.
    void releaseTexture() {
      if (textureReleased) return;
      textureReleased = true;
      if (producer != null) { producer.setCallback(null); producer.release(); }
      if (surfaceTexture != null) {
        if (surface != null) surface.release();
        surfaceTexture.release();
      }
    }
    void releasePlatform() {
      if (platformReleased) return;
      platformReleased = true;
      releaseTexture(); onAudioClosed();
    }

    // Called by the shared core's decode thread, never by the Dart isolate.
    @SuppressWarnings("unused") public void onFrame(int nextWidth, int nextHeight) {
      if (disposed || nextWidth <= 0 || nextHeight <= 0 || (width == nextWidth && height == nextHeight)) return;
      main.post(() -> {
        if (disposed || (width == nextWidth && height == nextHeight)) return;
        width = nextWidth; height = nextHeight;
        synchronized (decoderLock) {
          if (disposed) return;
          if (producer != null) {
            producer.setSize(width, height);
            surface = producer.getSurface();
          } else if (surfaceTexture != null) {
            surfaceTexture.surfaceTexture().setDefaultBufferSize(width, height);
          }
          if (decoder != 0) nativeSetSurface(decoder, surface);
        }
      });
    }
    @SuppressWarnings("unused") public void onAudioClosed() {
      synchronized (audioLock) {
        if (audio != null) {
          try { audio.pause(); audio.flush(); } finally { audio.release(); audio = null; }
          audioFramesWritten = 0; lastPlaybackHead = 0; playbackWrap = 0; audioGeneration++;
        }
      }
    }
    @SuppressWarnings("unused") public void onPaused(boolean value) {
      paused = value;
      synchronized (audioLock) {
        if (disposed || audio == null) return;
        if (value) {
          audio.pause(); audio.flush(); audioFramesWritten = 0;
          lastPlaybackHead = 0; playbackWrap = 0; audioGeneration++;
        }
        else audio.play();
      }
    }
    @SuppressWarnings("unused") public int onHardwareDecoder(String name) {
      if (name == null || name.isEmpty()) return -1;
      if (Build.VERSION.SDK_INT >= 29) {
        for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
          if (!info.isEncoder() && (name.equals(info.getName()) || name.equals(info.getCanonicalName()))) {
            if (info.isSoftwareOnly()) return 0;
            return info.isHardwareAccelerated() ? 1 : -1;
          }
        }
      }
      String lower = name.toLowerCase(java.util.Locale.ROOT);
      return lower.startsWith("c2.android.") || lower.startsWith("omx.google.") ? 0 : -1;
    }
    @SuppressWarnings("unused") public void onAudioState(ByteBuffer state) {
      synchronized (audioLock) {
        long played = 0;
        if (audio != null && !disposed) {
          long head = Integer.toUnsignedLong(audio.getPlaybackHeadPosition());
          if (head < lastPlaybackHead) playbackWrap += 1L << 32;
          lastPlaybackHead = head;
          played = Math.min(audioFramesWritten, playbackWrap + head);
        }
        state.order(ByteOrder.nativeOrder());
        state.putLong(played).putLong(Math.max(0, audioFramesWritten - played))
            .putLong(audioGeneration).putInt(!paused && !disposed && audio != null ? 1 : 0);
      }
    }
    @SuppressWarnings("unused") public long onPcm(ByteBuffer bytes) {
      if (disposed || paused || audio == null) return 0;
      synchronized (audioLock) {
        if (disposed || paused || audio == null) return 0;
        // The core retries unaccepted bytes. Never wait/sleep on its decode
        // thread, and never copy borrowed PCM into a Java heap array.
        int written = audio.write(bytes, bytes.remaining(), AudioTrack.WRITE_NON_BLOCKING);
        if (written > 0) audioFramesWritten += written / 4;
        return written < 0 ? written : written - written % 4;
      }
    }
  }

  private static native long nativeCreate(Object listener, Surface surface, int codec, int width,
      int height, long generation, String sourceId, long attachAddress, long detachAddress);
  private static native Map<String, Object> nativeBindings(long decoder);
  private static native void nativeSetSurface(long decoder, Surface surface);
  private static native Map<String, Object> nativeStatus(long decoder);
  private static native Map<String, Object> nativeSnapshot(long decoder, int maxWidth, int maxHeight);
  private static native void nativeSetPaused(long decoder, boolean paused);
  private static native void nativeSetVolume(long decoder, double volume);
  private static native void nativeDispose(long decoder);
}
