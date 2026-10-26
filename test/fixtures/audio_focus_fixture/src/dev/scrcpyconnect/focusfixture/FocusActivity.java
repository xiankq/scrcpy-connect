package dev.scrcpyconnect.focusfixture;

import android.app.Activity;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;

/** 仅测试使用的竞争应用，调用真实 AudioManager，不引入产品钩子。 */
public final class FocusActivity extends Activity {
    private AudioManager manager;
    private AudioFocusRequest request;
    private String runId = "unset", mode = "unset";
    private int result = -1, signal = 0;
    private boolean requested;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        manager = (AudioManager) getSystemService(AUDIO_SERVICE);
        setContentView(R.layout.activity_main);
        configure(getIntent());
    }
    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        configure(intent);
    }
    private void configure(Intent intent) {
        mode = intent.getStringExtra("mode");
        if ("release".equals(mode)) { release(); finish(); return; }
        runId = intent.getStringExtra("run_id");
        if (runId == null || !runId.matches("focus-[0-9]+")) { finish(); return; }
        if (!"transient".equals(mode) && !"permanent".equals(mode)) { finish(); return; }
        show();
    }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        if (!focused || requested || isFinishing() || "release".equals(mode)) return;
        requested = true;
        int gain = "permanent".equals(mode) ? AudioManager.AUDIOFOCUS_GAIN : AudioManager.AUDIOFOCUS_GAIN_TRANSIENT;
        request = new AudioFocusRequest.Builder(gain)
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener(change -> { signal = change; show(); }, new Handler(Looper.getMainLooper()))
            .build();
        result = manager.requestAudioFocus(request);
        show();
    }
    private void show() {
        ((TextView) findViewById(R.id.state)).setText("RUN=" + runId + " MODE=" + mode
            + " RESULT=" + result + " SIGNAL=" + signal);
    }
    private void release() {
        if (request != null) { manager.abandonAudioFocusRequest(request); request = null; }
    }
    @Override public void onDestroy() { release(); super.onDestroy(); }
}
