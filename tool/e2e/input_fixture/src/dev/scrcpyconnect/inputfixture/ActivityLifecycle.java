package dev.scrcpyconnect.inputfixture;

/** Host-only shell fixture; never called by or packaged with the product.
 * Setting the database key alone does not update ActivityManager's runtime flag.
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
