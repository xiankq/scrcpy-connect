package dev.scrcpyconnect.inputfixture;

/** 仅宿主使用的 shell 夹具，产品不调用也不打包。
 * 只修改数据库键不会更新 ActivityManager 的运行标志。
 */
public final class ActivityLifecycle {
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !(args[0].equals("1") || args[0].equals("0"))) {
            throw new IllegalArgumentException("Expected 0 or 1");
        }
        Object manager = Class.forName("android.app.ActivityManager")
            .getDeclaredMethod("getService").invoke(null);
        Class.forName("android.app.IActivityManager")
            .getMethod("setAlwaysFinish", boolean.class)
            .invoke(manager, args[0].equals("1"));
        System.out.println("setAlwaysFinish=" + args[0]);
    }
}
