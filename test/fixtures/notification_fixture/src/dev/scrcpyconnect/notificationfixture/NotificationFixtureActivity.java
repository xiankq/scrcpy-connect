package dev.scrcpyconnect.notificationfixture;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Person;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.util.AtomicFile;
import android.util.Log;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;

/** 独立测试 APK，不进入 Connect 或协同 JAR。 */
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

    private PendingIntent open(String runId, int id) {
        Intent intent = new Intent(this, NotificationFixtureActivity.class)
            .setAction(FixtureStore.PREFIX + "OPEN")
            .setData(Uri.parse("notificationfixture://" + runId + "/" + id + "/open"))
            .putExtra("runId", runId).putExtra("notificationId", id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, id, intent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private void postRequirement(String runId, int id, boolean ongoing) throws Exception {
        NotificationManager manager = getSystemService(NotificationManager.class);
        String tag = FixtureStore.tag(runId);
        manager.createNotificationChannel(new NotificationChannel(tag,
            "Temporary notification requirements test", NotificationManager.IMPORTANCE_DEFAULT));
        Notification notification = new Notification.Builder(this, tag)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(runId + "-" + id)
            .setContentText("Synthetic requirements source " + id)
            .setContentIntent(open(runId, id)).setOngoing(ongoing).build();
        if (ongoing) notification.flags |= Notification.FLAG_NO_CLEAR;
        manager.notify(tag, id, notification);
    }

    private void createRequirements(String runId) throws Exception {
        AtomicFile state = FixtureStore.file(this, "runs", runId);
        if (state.getBaseFile().exists()
            || FixtureStore.file(this, "cleanup", runId).getBaseFile().exists()) {
            throw new IllegalStateException("runId already exists");
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            throw new IllegalStateException("The isolated fixture requires notification permission");
        }
        postRequirement(runId, 0, false);
        postRequirement(runId, 1, false);
        postRequirement(runId, 4, true);
        FixtureStore.write(state, new JSONObject().put("runId", runId).put("status", "ready")
            .put("tag", FixtureStore.tag(runId)).put("notificationIds", new JSONArray(new int[]{0, 1, 4})));
    }

    private void postSnapshot(String runId, boolean update) throws Exception {
        NotificationManager manager = getSystemService(NotificationManager.class);
        String tag = FixtureStore.tag(runId);
        manager.createNotificationChannel(new NotificationChannel(tag,
            "Temporary snapshot consistency test", NotificationManager.IMPORTANCE_DEFAULT));
        Notification.Builder large = new Notification.Builder(this, tag)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Collapsed title")
            .setContentText("Collapsed preview")
            .setContentIntent(open(runId, 0))
            .setStyle(new Notification.BigTextStyle()
                .setBigContentTitle(update ? "Updated expanded title" : "Expanded title")
                .bigText(update ? "Updated real expanded body" : "Real expanded body"));
        manager.notify(tag, 0, large.build());
        if (!update) {
            manager.notify(tag, 1, new Notification.Builder(this, tag)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Inbox title")
                .setStyle(new Notification.InboxStyle()
                    .addLine("Alice: first message").addLine("Bob: latest message"))
                .build());
            manager.notify(tag, 2, new Notification.Builder(this, tag)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setStyle(new Notification.MessagingStyle(new Person.Builder().setName("Me").build())
                    .setConversationTitle("Team chat").setGroupConversation(true)
                    .addMessage("First", 1000, new Person.Builder().setName("Alice").build())
                    .addMessage("Latest", 2000, new Person.Builder().setName("Bob").build()))
                .build());
        }
        FixtureStore.write(FixtureStore.file(this, "runs", runId),
            new JSONObject().put("runId", runId).put("status", "ready")
            .put("tag", tag).put("notificationIds", new JSONArray(new int[]{0, 1, 2})));
    }

    private void cleanup(String runId) throws Exception {
        NotificationManager manager = getSystemService(NotificationManager.class);
        String tag = FixtureStore.tag(runId);
        AtomicFile state = FixtureStore.file(this, "runs", runId);
        AtomicFile cleanup = FixtureStore.file(this, "cleanup", runId);
        if (state.getBaseFile().exists()) {
            JSONObject closing = FixtureStore.read(state).put("status", "closing");
            FixtureStore.write(state, closing);
        }
        for (int id = 0; id < 6; id++) {
            manager.cancel(tag, id);
            // 这些身份包含 runId，不触碰其他运行的动作。
            open(runId, id).cancel();
        }
        manager.deleteNotificationChannel(tag);
        if (!cleanup.getBaseFile().exists()) {
            FixtureStore.write(cleanup, new JSONObject().put("runId", runId)
                .put("status", "cleaned"));
        }
        FixtureStore.file(this, "opens", runId).delete();
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
            if ((FixtureStore.PREFIX + "CREATE_SNAPSHOT").equals(action)) {
                AtomicFile active = FixtureStore.file(this, "runs", runId);
                if (active.getBaseFile().exists()
                    || FixtureStore.file(this, "cleanup", runId).getBaseFile().exists()) {
                    throw new IllegalStateException("runId already exists");
                }
                postSnapshot(runId, false);
            } else if ((FixtureStore.PREFIX + "UPDATE_SNAPSHOT").equals(action)) {
                if (!"ready".equals(FixtureStore.read(FixtureStore.file(this, "runs", runId)).optString("status"))) {
                    throw new IllegalStateException("Inactive run");
                }
                postSnapshot(runId, true);
            } else if ((FixtureStore.PREFIX + "CREATE_REQUIREMENTS").equals(action)) {
                createRequirements(runId);
            } else if ((FixtureStore.PREFIX + "POST_REQUIREMENT").equals(action)) {
                JSONObject active = FixtureStore.read(FixtureStore.file(this, "runs", runId));
                if (!"ready".equals(active.optString("status"))) throw new IllegalStateException("Inactive run");
                postRequirement(runId, 5, false);
            } else if ((FixtureStore.PREFIX + "WITHDRAW_REQUIREMENT").equals(action)) {
                getSystemService(NotificationManager.class).cancel(FixtureStore.tag(runId), 5);
            } else if ((FixtureStore.PREFIX + "OPEN").equals(action)) {
                AtomicFile receipt = FixtureStore.file(this, "opens", runId);
                int count = receipt.getBaseFile().exists() ? FixtureStore.read(receipt).getInt("count") : 0;
                FixtureStore.write(receipt, new JSONObject().put("runId", runId)
                    .put("notificationId", intent.getIntExtra("notificationId", -1)).put("count", count + 1));
            } else if (!(FixtureStore.PREFIX + "OPEN").equals(action)) {
                throw new IllegalArgumentException("Use an explicit fixture action");
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
