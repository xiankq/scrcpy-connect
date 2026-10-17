package dev.scrcpyconnect.notificationfixture;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.RemoteInput;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.util.AtomicFile;
import android.util.Log;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;

/** A separate test APK; never packaged into Connect or its companion JAR. */
public final class NotificationFixtureActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        handle(getIntent());
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handle(intent);
    }

    private PendingIntent reply(String runId, int id, boolean mutable) {
        Intent intent = new Intent(this, ReplyReceiver.class)
            .setAction(FixtureStore.PREFIX + "REPLY")
            .setData(Uri.parse("notificationfixture://" + runId + "/" + id + "/reply"))
            .putExtra("runId", runId).putExtra("notificationId", id);
        return PendingIntent.getBroadcast(this, id, intent,
            (mutable ? PendingIntent.FLAG_MUTABLE : PendingIntent.FLAG_IMMUTABLE)
                | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private PendingIntent open(String runId, int id) {
        Intent intent = new Intent(this, NotificationFixtureActivity.class)
            .setAction(FixtureStore.PREFIX + "OPEN")
            .setData(Uri.parse("notificationfixture://" + runId + "/" + id + "/open"))
            .putExtra("runId", runId).putExtra("notificationId", id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, id, intent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private void create(String runId) throws Exception {
        AtomicFile state = FixtureStore.file(this, "runs", runId);
        if (state.getBaseFile().exists()
            || FixtureStore.file(this, "cleanup", runId).getBaseFile().exists()) {
            throw new IllegalStateException("runId already exists");
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            throw new IllegalStateException("The test harness must grant only this new fixture's notification permission");
        }
        NotificationManager manager = getSystemService(NotificationManager.class);
        String tag = FixtureStore.tag(runId);
        manager.createNotificationChannel(new NotificationChannel(tag,
            "Temporary notification interoperability test", NotificationManager.IMPORTANCE_DEFAULT));
        RemoteInput input = new RemoteInput.Builder(FixtureStore.RESULT_KEY).setLabel("Synthetic reply").build();
        PendingIntent cancelled = null;
        for (int id = 0; id < 4; id++) {
            PendingIntent content = open(runId, id);
            if (id == 3) cancelled = content;
            Notification.Builder notification = new Notification.Builder(this, tag)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(runId + "-" + id)
                .setContentText("Synthetic notification interoperability fixture")
                .setContentIntent(content);
            if (id < 3) {
                Notification.Action.Builder action = new Notification.Action.Builder(null,
                    "Reply", reply(runId, id, id != 1)).setAuthenticationRequired(id == 2);
                // The OS rejects immutable PendingIntents carrying RemoteInput.
                if (id != 1) action.addRemoteInput(input);
                notification.addAction(action.build());
            }
            manager.notify(tag, id, notification.build());
        }
        cancelled.cancel();
        FixtureStore.write(state, new JSONObject().put("runId", runId).put("status", "ready")
            .put("tag", tag).put("channel", tag).put("notificationIds", new JSONArray(new int[]{0, 1, 2, 3})));
    }

    private void cleanup(String runId) throws Exception {
        NotificationManager manager = getSystemService(NotificationManager.class);
        String tag = FixtureStore.tag(runId);
        AtomicFile state = FixtureStore.file(this, "runs", runId);
        AtomicFile receipt = FixtureStore.file(this, "receipts", runId);
        AtomicFile cleanup = FixtureStore.file(this, "cleanup", runId);
        // Activity callbacks and BroadcastReceiver.onReceive run on this app's
        // main thread. Closing eligibility here bounds which deliveries may
        // write a receipt; a queued callback cannot race the final snapshot.
        if (state.getBaseFile().exists()) {
            JSONObject closing = FixtureStore.read(state).put("status", "closing");
            FixtureStore.write(state, closing);
        }
        for (int id = 0; id < 4; id++) {
            manager.cancel(tag, id);
            // These identities include runId; no other run's actions are touched.
            open(runId, id).cancel();
            if (id < 3) reply(runId, id, id != 1).cancel();
        }
        manager.deleteNotificationChannel(tag);
        // Preserve the final delivery count until the owner uninstalls this
        // test APK. Retrying cleanup must not replace that evidence with null.
        if (!cleanup.getBaseFile().exists()) {
            Object finalReceipt = receipt.getBaseFile().exists()
                ? FixtureStore.read(receipt) : JSONObject.NULL;
            FixtureStore.write(cleanup, new JSONObject().put("runId", runId)
                .put("status", "cleaned").put("finalReceipt", finalReceipt));
        }
        receipt.delete();
        state.delete();
        finishAndRemoveTask();
    }

    private void handle(Intent intent) {
        String runId = null;
        try {
            runId = FixtureStore.runId(intent.getStringExtra("runId"));
            String action = intent.getAction();
            if ((FixtureStore.PREFIX + "CLEANUP").equals(action)) {
                cleanup(runId);
                return;
            }
            if ((FixtureStore.PREFIX + "CREATE").equals(action)) {
                create(runId);
            } else if (!(FixtureStore.PREFIX + "OPEN").equals(action)) {
                throw new IllegalArgumentException("Use an explicit CREATE, OPEN or CLEANUP action");
            }
            TextView text = new TextView(this);
            text.setText("Notification fixture\n" + runId);
            text.setPadding(32, 32, 32, 32);
            setContentView(text);
        } catch (Exception error) {
            Log.e("NotificationFixture", "Fixture action failed", error);
            if (runId != null) {
                try {
                    AtomicFile state = FixtureStore.file(this, "runs", runId);
                    if (!state.getBaseFile().exists()) {
                        FixtureStore.write(state, new JSONObject().put("runId", runId)
                            .put("status", "error").put("error", error.toString()));
                    }
                } catch (Exception storageError) {
                    Log.e("NotificationFixture", "Cannot publish fixture failure", storageError);
                }
            }
            finishAndRemoveTask();
        }
    }
}
