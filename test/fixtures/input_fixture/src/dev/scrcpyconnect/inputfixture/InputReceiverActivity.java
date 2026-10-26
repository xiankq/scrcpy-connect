package dev.scrcpyconnect.inputfixture;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.widget.TextView;

/** 需显式启用的测试接收器，不属于产品依赖或被控能力。 */
public final class InputReceiverActivity extends Activity {
    private String runId = "invalid";
    private String sessionId = "invalid";
    private int initialDowns;
    private int repeats;
    private int ups;
    private int duplicateDowns;
    private int orphanUps;
    private boolean pressed;
    private long downAt;
    private long upAt;
    private String last = "NONE";
    private TextView state;

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(R.layout.activity_main);
        state = findViewById(R.id.state);
        arm(getIntent());
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        arm(intent);
    }

    private void arm(Intent intent) {
        String nextRun = intent.getStringExtra("run_id");
        String nextSession = intent.getStringExtra("session_id");
        if (nextRun == null || !nextRun.matches("input-[0-9]+") ||
                nextSession == null || !nextSession.matches("[A-Za-z0-9_-]{1,128}")) {
            state.setText("INVALID_MARKER");
            return;
        }
        runId = nextRun;
        sessionId = nextSession;
        initialDowns = repeats = ups = duplicateDowns = orphanUps = 0;
        pressed = false;
        downAt = upAt = 0;
        last = "NONE";
        render();
    }

    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_DPAD_DOWN) {
            return super.dispatchKeyEvent(event);
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            if (event.getRepeatCount() > 0) {
                repeats++;
                // 按键保持期间维持界面稳定，便于 UiAutomation 取得空闲快照；下一次 UP 发布实际重复次数。
                //
                return true;
            }
            if (pressed) duplicateDowns++;
            initialDowns++;
            pressed = true;
            downAt = SystemClock.uptimeMillis();
            last = "DOWN";
        } else if (event.getAction() == KeyEvent.ACTION_UP) {
            if (!pressed) orphanUps++;
            ups++;
            pressed = false;
            upAt = SystemClock.uptimeMillis();
            last = "UP";
        } else {
            return super.dispatchKeyEvent(event);
        }
        render();
        return true;
    }

    private void render() {
        state.setText("RUN=" + runId + " SESSION=" + sessionId +
                " KEY=20 INITIAL_DOWN=" + initialDowns + " UP=" + ups +
                " PRESSED=" + pressed + " LAST=" + last +
                " REPEATS=" + repeats + " DUPLICATE_DOWN=" + duplicateDowns +
                " ORPHAN_UP=" + orphanUps + " DOWN_AT=" + downAt + " UP_AT=" + upAt);
    }
}
