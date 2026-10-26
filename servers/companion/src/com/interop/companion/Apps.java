package com.interop.companion;

import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.Process;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Field;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** 被控设备拥有的真实应用任务及栅格化包图标，不回退为已安装应用列表。 */
final class Apps {
    private static final int MAX_TASKS = 512;
    private static final int ICON_SIZE = 96;
    private static final int MAX_ICON_BYTES = 128 * 1024;

    static boolean applicationTask(boolean running, int activities, int activityType, int taskUser, int currentUser) {
        // TaskInfo 的 activity type 1 表示 STANDARD；HOME、RECENTS、ASSISTANT 和 DREAM 不属于应用。
        return running && activities > 0 && activityType == 1 && taskUser == currentUser;
    }

    static Context currentUserContext(Context context, int user) throws Exception {
        try {
            Class<?> handle = Class.forName("android.os.UserHandle");
            Object identity = handle.getConstructor(int.class).newInstance(user);
            Context current = (Context) Context.class.getMethod("createPackageContextAsUser", String.class, int.class, handle)
                .invoke(context, "com.android.shell", 0, identity);
            if ((Integer) Main.invoke(current, "getUserId") != user)
                throw new Main.Failure("user_unavailable", "The package context does not belong to the verified current user");
            return current;
        } catch (java.lang.reflect.InvocationTargetException failure) {
            if (failure.getCause() instanceof Exception) throw (Exception) failure.getCause();
            throw failure;
        }
    }

    private static void requireTaskAccess(Context context) throws Exception {
        if (context.checkPermission("android.permission.REAL_GET_TASKS", Process.myPid(), Process.myUid()) == PackageManager.PERMISSION_GRANTED) return;
        // AOSP 仅允许特权 UID 使用旧 GET_TASKS；缺少此检查时，getRunningTasks 会静默只返回 shell/home，不能据此展示空列表。
        //
        if (context.checkPermission("android.permission.GET_TASKS", Process.myPid(), Process.myUid()) == PackageManager.PERMISSION_GRANTED
            && Boolean.TRUE.equals(Main.invoke(Main.service("package", "android.content.pm.IPackageManager"), "isUidPrivileged", Process.myUid()))) return;
        throw new Main.Failure("permission_denied", "The shell identity cannot enumerate application tasks");
    }

    @SuppressWarnings("deprecation")
    static JSONObject running(Context context, int user) throws Exception {
        if (Build.VERSION.SDK_INT < 29) throw new Main.Failure("apps_running_unavailable", "Verified task/user metadata requires Android 10 or later");
        requireTaskAccess(context);
        Context current = currentUserContext(context, user);
        PackageManager packages = current.getPackageManager();
        ActivityManager manager = (ActivityManager) current.getSystemService(Context.ACTIVITY_SERVICE);
        if (manager == null) throw new Main.Failure("apps_running_unavailable", "Activity service is absent");
        List<ActivityManager.RunningTaskInfo> tasks = manager.getRunningTasks(MAX_TASKS);
        if (tasks == null) throw new Main.Failure("apps_running_unavailable", "Activity service did not return a task snapshot");
        if (tasks.size() >= MAX_TASKS) throw new Main.Failure("apps_limit", "Application task snapshot exceeds the verified bound");
        JSONArray apps = new JSONArray();
        Set<String> seen = new HashSet<>();
        for (ActivityManager.RunningTaskInfo task : tasks) {
            // 通过反射读取新版本元数据，避免 API21 图标请求链接到 TaskInfo。
            Field userField = task.getClass().getField("userId");
            int taskUser = userField.getInt(task);
            int type = (Integer) Main.invoke(task, "getActivityType");
            boolean active = task.getClass().getField("isRunning").getBoolean(task);
            if (!applicationTask(active, task.numActivities, type, taskUser, user) || task.baseActivity == null) continue;
            String name = task.baseActivity.getPackageName();
            if (!seen.add(name)) continue;
            try {
                ApplicationInfo info = packages.getApplicationInfo(name, 0);
                apps.put(new JSONObject().put("name", packages.getApplicationLabel(info).toString())
                    .put("packageName", name).put("system", (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0)
                    .put("taskId", task.id).put("userId", taskUser));
            } catch (PackageManager.NameNotFoundException disappeared) {
                // 包可能在 Binder 快照与元数据读取之间被移除。
            }
        }
        return new JSONObject().put("apps", apps).put("source", "runningTasks").put("live", true).put("userId", user);
    }

    static JSONObject icon(Context context, JSONObject request, int user) throws Exception {
        String name = request.optString("packageName");
        if (name.isEmpty() || name.length() > 255 || !name.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*"))
            throw new Main.Failure("invalid_argument", "A valid target package name is required");
        Context current = currentUserContext(context, user);
        PackageManager packages = current.getPackageManager();
        final Drawable icon;
        try {
            // 先用 getApplicationInfo 确认包存在，避免 PackageManager 返回缺失包的默认图标。
            ApplicationInfo info = packages.getApplicationInfo(name, 0);
            if (info.icon == 0) throw new Main.Failure("app_icon_unavailable", "The package does not declare an application icon");
            icon = packages.getResourcesForApplication(info).getDrawable(info.icon);
        } catch (PackageManager.NameNotFoundException missing) {
            throw new Main.Failure("app_not_found", "The target package no longer exists for the current user");
        } catch (android.content.res.Resources.NotFoundException missing) {
            throw new Main.Failure("app_icon_unavailable", "The target package icon resource is unavailable");
        }
        if (icon == null) throw new Main.Failure("app_icon_unavailable", "The target package icon is unavailable");
        Bitmap bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888);
        try {
            icon.setBounds(0, 0, ICON_SIZE, ICON_SIZE);
            icon.draw(new Canvas(bitmap));
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes) || bytes.size() > MAX_ICON_BYTES)
                throw new Main.Failure("app_icon_unavailable", "The target icon could not be encoded within its byte limit");
            return new JSONObject().put("packageName", name).put("mimeType", "image/png")
                .put("dataBase64", Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP))
                .put("width", ICON_SIZE).put("height", ICON_SIZE)
                .put("userId", (Integer) Main.invoke(current, "getUserId"));
        } finally { bitmap.recycle(); }
    }
}
