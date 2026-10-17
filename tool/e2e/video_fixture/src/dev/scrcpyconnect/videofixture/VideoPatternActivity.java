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

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        pattern = new Pattern();
        setContentView(pattern);
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        counter = 0;
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
            paint.setColor(Color.BLACK);
            paint.setTextSize(getWidth() / 12f);
            canvas.drawText("VIDEO " + counter, getWidth() / 16f, getHeight() * .85f, paint);
        }
    }
}
