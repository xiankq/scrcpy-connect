package dev.scrcpyconnect.videofixture;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;

/** Independent lab target, never installed by or bundled with the product. */
public final class VideoPatternActivity extends Activity {
    private Pattern pattern;
    private int counter;
    private boolean motion;
    private int frame;
    private int sequence;
    private int drawnSequence = -1;
    private String timelineRun;

    private void configure(Intent intent) {
        motion = intent.getBooleanExtra("motion", false);
        String run = intent.getStringExtra("timelineRun");
        timelineRun = run != null && run.matches("[a-zA-Z0-9_-]{1,80}") ? run : null;
    }

    private void trace(String kind, long startUs, long eventTimeMs,
            long startBootBeforeUs, long startBootAfterUs) {
        if (timelineRun == null) return;
        long bootBeforeUs = SystemClock.elapsedRealtimeNanos() / 1000;
        long nanoUs = System.nanoTime() / 1000;
        long bootAfterUs = SystemClock.elapsedRealtimeNanos() / 1000;
        Log.i("ConnectVideoClock", "{\"run\":\"" + timelineRun
            + "\",\"kind\":\"" + kind + "\",\"sequence\":" + sequence
            + ",\"counter\":" + counter + ",\"nanoUs\":" + nanoUs
            + ",\"bootBeforeUs\":" + bootBeforeUs + ",\"bootAfterUs\":" + bootAfterUs
            + ",\"drawStartUs\":" + startUs + ",\"eventUptimeMs\":" + eventTimeMs
            + ",\"drawStartBootBeforeUs\":" + startBootBeforeUs
            + ",\"drawStartBootAfterUs\":" + startBootAfterUs + "}");
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        configure(getIntent());
        pattern = new Pattern();
        setContentView(pattern);
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        counter = 0;
        sequence = 0;
        drawnSequence = -1;
        configure(intent);
        pattern.invalidate();
    }

    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_DPAD_DOWN) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_UP) {
            counter = (counter + 1) & 15;
            sequence++;
            trace("input", 0, event.getEventTime(), 0, 0);
            pattern.invalidate();
        }
        return true;
    }

    private final class Pattern extends View {
        private final Paint paint = new Paint();
        Pattern() { super(VideoPatternActivity.this); }
        @Override protected void onDraw(Canvas canvas) {
            long bootBeforeUs = timelineRun == null ? 0 : SystemClock.elapsedRealtimeNanos() / 1000;
            long startUs = timelineRun == null ? 0 : System.nanoTime() / 1000;
            long bootAfterUs = timelineRun == null ? 0 : SystemClock.elapsedRealtimeNanos() / 1000;
            for (int bit = 0; bit < 4; bit++) {
                paint.setColor((counter & (1 << bit)) != 0 ? 0xffff4040 : 0xff40c0ff);
                canvas.drawRect(getWidth() * bit / 4f, 0,
                    getWidth() * (bit + 1) / 4f, getHeight(), paint);
            }
            if (motion) {
                // Changing tiles create sustained encode/transport/decode load.
                // Keep the middle band unchanged for the counter oracle used
                // by both decoded snapshots and Android composition captures.
                for (int y = 0; y < getHeight(); y += 64) {
                    for (int x = 0; x < getWidth(); x += 64) {
                        int seed = frame * 1664525 + x * 1013904223 + y * 69069;
                        seed ^= seed >>> 16;
                        paint.setColor(0xff000000 | (seed & 0x00ffffff));
                        if (y < getHeight() * .4f) {
                            canvas.drawRect(x, y, x + 64,
                                Math.min(y + 64, getHeight() * .4f), paint);
                        } else if (y >= getHeight() * .6f) {
                            canvas.drawRect(x, y, x + 64, y + 64, paint);
                        }
                    }
                }
                frame++;
                postInvalidateOnAnimation();
            }
            paint.setColor(Color.BLACK);
            paint.setTextSize(getWidth() / 12f);
            canvas.drawText("VIDEO " + counter + (motion ? " / " + frame : ""),
                getWidth() / 16f, getHeight() * .85f, paint);
            if (drawnSequence != sequence) {
                drawnSequence = sequence;
                trace("draw", startUs, 0, bootBeforeUs, bootAfterUs);
            }
        }
    }
}
