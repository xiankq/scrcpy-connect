package dev.scrcpyconnect.videofixture;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;

/** Independent lab target, never installed by or bundled with the product. */
public final class VideoPatternActivity extends Activity {
    private Pattern pattern;
    private int counter;
    private boolean motion;
    private int frame;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        motion = getIntent().getBooleanExtra("motion", false);
        pattern = new Pattern();
        setContentView(pattern);
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        counter = 0;
        motion = intent.getBooleanExtra("motion", false);
        pattern.invalidate();
    }

    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_DPAD_DOWN) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_UP) {
            counter = (counter + 1) & 15;
            pattern.invalidate();
        }
        return true;
    }

    private final class Pattern extends View {
        private final Paint paint = new Paint();
        Pattern() { super(VideoPatternActivity.this); }
        @Override protected void onDraw(Canvas canvas) {
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
        }
    }
}
