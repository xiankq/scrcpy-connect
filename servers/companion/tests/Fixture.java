package com.interop.companion;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Looper;
import android.provider.Settings;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/** Test-only real notifications and PendingIntents; never included in companion.jar. */
public final class Fixture {
    public static void main(String[] args) throws Exception {
        String tag = "interop-fixture-" + UUID.randomUUID();
        Looper.prepareMainLooper();
        Object thread = Class.forName("android.app.ActivityThread")
            .getMethod("systemMain").invoke(null);
        Context system = (Context) Main.invoke(thread, "getSystemContext");
        Context context = system.createPackageContext("com.android.shell", 0);
        Object manager = Main.service("notification", "android.app.INotificationManager");
        Object channels = Class.forName("android.content.pm.ParceledListSlice")
            .getConstructor(List.class)
            .newInstance(Collections.singletonList(new NotificationChannel(
                tag, "Interop temporary E2E", android.app.NotificationManager.IMPORTANCE_DEFAULT)));
        Main.invoke(manager, "createNotificationChannels", "com.android.shell", channels);

        PendingIntent open = contentIntent(context, 1);
        PendingIntent cancelled = contentIntent(context, 2);
        try {
            for (int id = 0; id < 4; id++) {
                Notification.Builder notification = new Notification.Builder(context, tag)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(tag + "-" + id)
                    .setContentText("Synthetic interoperability fixture")
                    .setContentIntent(id == 3 ? cancelled : open);
                Main.invoke(manager, "enqueueNotificationWithTag",
                    "com.android.shell", "com.android.shell", tag, id, notification.build(), 0);
            }
            cancelled.cancel();
            System.out.println(new JSONObject().put("event", "fixture.ready").put("tag", tag));
            System.out.flush();
            new BufferedReader(new InputStreamReader(System.in)).readLine();
        } finally {
            for (int id = 0; id < 4; id++) {
                Main.invoke(manager, "cancelNotificationWithTag",
                    "com.android.shell", "com.android.shell", tag, id, 0);
            }
            Main.invoke(manager, "deleteNotificationChannel", "com.android.shell", tag);
            open.cancel();
            cancelled.cancel();
        }
        System.exit(0);
    }

    private static PendingIntent contentIntent(Context context, int request) {
        Intent intent = new Intent(Settings.ACTION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(context, request, intent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
}
