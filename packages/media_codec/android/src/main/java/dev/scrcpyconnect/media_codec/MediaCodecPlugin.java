package dev.scrcpyconnect.media_codec;

import android.graphics.Bitmap;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.PixelCopy;
import android.view.Surface;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
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
    for (Session session : sessions.values()) dispose(session, null);
    sessions.clear();
    worker.shutdown();
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
          value.put("textureId", session.producer == null ? -1L : session.producer.id());
          value.put("width", session.width);
          value.put("height", session.height);
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
            session.paused = Boolean.TRUE.equals(args.get("paused"));
            nativeSetPaused(session.decoder, session.paused);
            if (session.audio != null) {
              if (session.paused) { session.audio.pause(); session.audio.flush(); }
              else session.audio.play();
            }
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
    worker.execute(() -> {
      session.closeNative(); // Detach drains Rust callbacks before releasing Surface/AudioTrack.
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
        if (session.producer == null || session.disposed || Build.VERSION.SDK_INT < 24) {
          result.success(null); return;
        }
        // MediaCodec Surface buffers intentionally never travel through CPU memory during playback.
        // An explicit snapshot is the only path that reads the Android Surface back.
        double scale = Math.min(1.0, Math.min((double) maxWidth / session.width, (double) maxHeight / session.height));
        Bitmap bitmap = Bitmap.createBitmap(Math.max(1, (int) (session.width * scale)),
            Math.max(1, (int) (session.height * scale)), Bitmap.Config.ARGB_8888);
        try {
          PixelCopy.request(session.producer.getSurface(), bitmap, status -> {
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
    final AudioTrack audio;
    volatile boolean disposed;
    volatile boolean paused;
    volatile int width;
    volatile int height;
    volatile Surface surface;
    long decoder;

    Session(long id, Map<?, ?> config, boolean isAudio) {
      this.id = id; this.config = config;
      width = Math.max(1, (int) number(config, "width", 1));
      height = Math.max(1, (int) number(config, "height", 1));
      if (isAudio) {
        producer = null;
        int minimum = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        if (Build.VERSION.SDK_INT >= 23) {
          AudioTrack.Builder builder = new AudioTrack.Builder()
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(new AudioFormat.Builder().setSampleRate(48000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(Math.max(minimum, 7680));
          if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY);
          audio = builder.build();
        } else {
          audio = new AudioTrack(AudioManager.STREAM_MUSIC, 48000, AudioFormat.CHANNEL_OUT_STEREO,
              AudioFormat.ENCODING_PCM_16BIT, Math.max(minimum, 7680), AudioTrack.MODE_STREAM);
        }
        if (audio.getState() != AudioTrack.STATE_INITIALIZED) {
          audio.release(); throw new IllegalStateException("PCM audio output is unavailable");
        }
        audio.play();
      } else {
        audio = null;
        producer = textures.createSurfaceProducer();
        producer.setSize(width, height);
        surface = producer.getSurface();
        producer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
          @Override public void onSurfaceCleanup() {
            worker.execute(Session.this::closeNative);
          }
          @Override public void onSurfaceAvailable() {
            surface = producer.getSurface();
            Surface available = surface;
            worker.execute(() -> { if (!disposed && decoder == 0) open(available); });
          }
        });
      }
    }

    void open() { open(surface); }
    void open(Surface surface) {
      if (disposed || decoder != 0) return;
      decoder = nativeCreate(this, surface, audio != null ? 100 : codec(config.get("codec")),
          width, height, number(config, "generation", 0), (String) config.get("sourceId"),
          number(config, "attachAddress", 0), number(config, "detachAddress", 0));
      if (decoder == 0) throw new IllegalStateException("Unable to attach native media output");
      if (paused) nativeSetPaused(decoder, true);
    }
    void closeNative() {
      if (decoder != 0) { nativeDispose(decoder); decoder = 0; }
    }
    void releasePlatform() {
      if (producer != null) { producer.setCallback(null); producer.release(); }
      if (audio != null) { audio.pause(); audio.flush(); audio.release(); }
    }

    // Called by the shared core's decode thread, never by the Dart isolate.
    @SuppressWarnings("unused") public void onFrame(int nextWidth, int nextHeight) {
      if (disposed || nextWidth <= 0 || nextHeight <= 0 || (width == nextWidth && height == nextHeight)) return;
      main.post(() -> {
        if (disposed || (width == nextWidth && height == nextHeight)) return;
        width = nextWidth; height = nextHeight;
        worker.execute(() -> {
          closeNative();
          main.post(() -> {
            if (disposed) return;
            producer.setSize(width, height);
            surface = producer.getSurface();
            Surface available = surface;
            worker.execute(() -> { if (!disposed) open(available); });
          });
        });
      });
    }
    @SuppressWarnings("unused") public long onPcm(byte[] bytes) {
      if (disposed || paused || audio == null) return 0;
      int offset = 0;
      long deadline = SystemClock.elapsedRealtime() + 80;
      while (offset < bytes.length && !disposed && !paused) {
        int written = audio.write(bytes, offset, bytes.length - offset, AudioTrack.WRITE_NON_BLOCKING);
        if (written < 0) return written;
        offset += written;
        if (offset < bytes.length) {
          if (SystemClock.elapsedRealtime() >= deadline) break;
          SystemClock.sleep(1);
        }
      }
      return offset;
    }
  }

  private static native long nativeCreate(Object listener, Surface surface, int codec, int width,
      int height, long generation, String sourceId, long attachAddress, long detachAddress);
  private static native Map<String, Object> nativeStatus(long decoder);
  private static native Map<String, Object> nativeSnapshot(long decoder, int maxWidth, int maxHeight);
  private static native void nativeSetPaused(long decoder, boolean paused);
  private static native void nativeSetVolume(long decoder, double volume);
  private static native void nativeDispose(long decoder);
}
