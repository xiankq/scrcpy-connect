package dev.scrcpyconnect.notificationfixture;

import android.app.RemoteInput;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.AtomicFile;
import android.util.Log;
import org.json.JSONObject;

/** Receives the original mutable PendingIntent in an AMS-managed app process. */
public final class ReplyReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        try {
            if (!FixtureStore.PREFIX.concat("REPLY").equals(intent.getAction())) {
                throw new IllegalArgumentException("Unexpected fixture action");
            }
            String runId = FixtureStore.runId(intent.getStringExtra("runId"));
            JSONObject run = FixtureStore.read(FixtureStore.file(context, "runs", runId));
            if (!runId.equals(run.getString("runId")) || !"ready".equals(run.getString("status"))) {
                throw new IllegalStateException("The fixture run is not active");
            }
            int notificationId = intent.getIntExtra("notificationId", -1);
            if (notificationId != 0 && notificationId != 2) {
                throw new IllegalArgumentException("Not an original reply notification");
            }
            Bundle results = RemoteInput.getResultsFromIntent(intent);
            CharSequence text = results == null ? null : results.getCharSequence(FixtureStore.RESULT_KEY);
            if (text == null || text.length() == 0 || text.length() > 16384) {
                throw new IllegalArgumentException("The original RemoteInput result is missing or invalid");
            }
            AtomicFile file = FixtureStore.file(context, "receipts", runId);
            int count = file.getBaseFile().exists() ? FixtureStore.read(file).getInt("count") : 0;
            JSONObject receipt = new JSONObject()
                .put("runId", runId)
                .put("messageId", runId + ":" + notificationId)
                .put("notificationId", notificationId)
                .put("text", text.toString())
                .put("count", count + 1);
            FixtureStore.write(file, receipt);
        } catch (Exception error) {
            Log.e("NotificationFixture", "Original reply receiver failed", error);
        }
    }
}
