package com.interop.companion;

import java.io.*;
import java.util.concurrent.TimeUnit;

/** Host contract test: the API21 Process boundary has only exitValue/destroy. */
public final class CompatibilityTest {
    public static final class LegacyCalls {
        boolean listening, opened;
        public void listenForSubscriber(long subscription, String pkg, Object token, int events, boolean notify) {
            if (subscription != Long.MAX_VALUE || !pkg.equals("com.android.shell") || token == null || events != (notify ? 32 : 0)) throw new AssertionError("Wrong API21 listener attribution");
            listening = notify;
        }
        public int getCallState() { return 1; }
        public void showInCallScreen(boolean dialpad) { if (dialpad) throw new AssertionError("Unexpected dialpad"); opened = true; }
    }
    public static final class MarshmallowCalls {
        boolean listening;
        public void listenForSubscriber(int subscription, String pkg, Object token, int events, boolean notify) {
            if (subscription != Integer.MAX_VALUE || !pkg.equals("com.android.shell") || token == null || events != (notify ? 32 : 0)) throw new AssertionError("Wrong API23 listener attribution");
            listening = notify;
        }
    }
    public static final class Android11Calls {
        boolean listening;
        public void listenForSubscriber(int subscription, String pkg, String tag, Object token, int events, boolean notify) {
            if (subscription != Integer.MAX_VALUE || !pkg.equals("com.android.shell") || tag != null || token == null || events != (notify ? 32 : 0)) throw new AssertionError("Wrong API30 listener attribution");
            listening = notify;
        }
    }
    public static final class ModernCalls {
        boolean listening;
        public void listenWithEventList(boolean fine, boolean coarse, int subscription, String pkg, String tag, Object token, int[] events, boolean notify) {
            if (!fine || !coarse || subscription != Integer.MAX_VALUE || !pkg.equals("com.android.shell") || tag != null || token == null || events.length != (notify ? 1 : 0) || notify && events[0] != 6) throw new AssertionError("Wrong modern listener attribution");
            listening = notify;
        }
        public int getCallStateUsingPackage(String pkg, String tag) {
            if (!pkg.equals("com.android.shell") || tag != null) throw new AssertionError("Wrong call-state attribution");
            return 2;
        }
        public int getCallState() { throw new AssertionError("Modern attribution bypassed"); }
    }
    public static final class DeniedCalls {
        public int getCallStateUsingPackage(String pkg, String tag) { throw new SecurityException("denied"); }
        public int getCallState() { throw new AssertionError("Permission denial bypassed"); }
    }
    public static final class LegacyAppOps {
        public static final int OP_READ_CLIPBOARD = 29, OP_WRITE_CLIPBOARD = 30;
        public int checkOpNoThrow(String operation, int uid, String pkg) {
            throw new IllegalArgumentException("Unknown operation string: " + operation);
        }
        public int checkOpNoThrow(int operation, int uid, String pkg) {
            if (uid != 2000 || !pkg.equals("com.android.shell")) throw new AssertionError("Wrong clipboard attribution");
            if (operation == 29) return 0;
            if (operation == 30) return 1;
            throw new AssertionError("Wrong legacy clipboard operation");
        }
    }
    public static final class ModernAppOps {
        public int checkOpNoThrow(String operation, int uid, String pkg) {
            if (uid != 2000 || !pkg.equals("com.android.shell") || !operation.equals("android:read_clipboard")) throw new AssertionError("Wrong modern clipboard attribution");
            return 1;
        }
        public int checkOpNoThrow(int operation, int uid, String pkg) { throw new AssertionError("Modern AppOps denial bypassed"); }
    }
    public static final class DeniedAppOps {
        public int checkOpNoThrow(String operation, int uid, String pkg) { throw new SecurityException("denied"); }
        public int checkOpNoThrow(int operation, int uid, String pkg) { throw new AssertionError("AppOps permission denial bypassed"); }
    }
    public static final class InvalidAppOps {
        public int checkOpNoThrow(String operation, int uid, String pkg) { throw new IllegalArgumentException("Invalid caller"); }
        public int checkOpNoThrow(int operation, int uid, String pkg) { throw new AssertionError("Unexpected AppOps failure bypassed"); }
    }
    private static final class LegacyProcess extends Process {
        boolean exited;
        public OutputStream getOutputStream() { return new ByteArrayOutputStream(); }
        public InputStream getInputStream() { return new ByteArrayInputStream(new byte[0]); }
        public InputStream getErrorStream() { return new ByteArrayInputStream(new byte[0]); }
        public int waitFor() { throw new AssertionError("Unbounded process wait"); }
        public boolean waitFor(long timeout, TimeUnit unit) { throw new AssertionError("API26 process wait"); }
        public boolean isAlive() { throw new AssertionError("API26 process liveness"); }
        public int exitValue() { if (!exited) throw new IllegalThreadStateException(); return 0; }
        public void destroy() { exited = true; }
    }
    public static void main(String[] args) throws Exception {
        LegacyProcess process = new LegacyProcess();
        if (!Processes.alive(process)) throw new AssertionError("Running process reported exited");
        long start = System.nanoTime();
        if (Processes.await(process, 40)) throw new AssertionError("Running process reported reaped");
        if (TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start) > 1000) throw new AssertionError("Unbounded process wait");
        process.destroy();
        if (!Processes.await(process, 0) || Processes.alive(process)) throw new AssertionError("Exited process not reaped");
        System.out.println("PASS: API21 owned-process lifecycle");
        LegacyCalls calls = new LegacyCalls();
        Object token = new Object();
        CallServices.listen(calls, token, true);
        if (!calls.listening || CallServices.state(calls) != 1) throw new AssertionError("Legacy call observation unavailable");
        CallServices.listen(calls, token, false);
        if (calls.listening) throw new AssertionError("Legacy call listener not removed");
        CallServices.openSystemUi(calls);
        if (!calls.opened) throw new AssertionError("API21 original system UI not requested");
        System.out.println("PASS: API21 read-only call observation");
        MarshmallowCalls marshmallow = new MarshmallowCalls();
        CallServices.listen(marshmallow, token, true);
        if (!marshmallow.listening) throw new AssertionError("API23 listener unavailable");
        CallServices.listen(marshmallow, token, false);
        if (marshmallow.listening) throw new AssertionError("API23 listener not removed");
        Android11Calls android11 = new Android11Calls();
        CallServices.listen(android11, token, true);
        if (!android11.listening) throw new AssertionError("API30 listener unavailable");
        CallServices.listen(android11, token, false);
        if (android11.listening) throw new AssertionError("API30 listener not removed");
        ModernCalls modern = new ModernCalls();
        CallServices.listen(modern, token, true);
        if (!modern.listening || CallServices.state(modern) != 2) throw new AssertionError("Modern call state unavailable");
        CallServices.listen(modern, token, false);
        if (modern.listening) throw new AssertionError("Modern listener not removed");
        try { CallServices.state(new DeniedCalls()); throw new AssertionError("Permission denial lost"); }
        catch (SecurityException expected) { }
        try { CallServices.listen(new Object(), token, true); throw new AssertionError("Unknown signature accepted"); }
        catch (NoSuchMethodException expected) { }
        System.out.println("PASS: API23/30/31+ call signatures and permission boundary");
        LegacyAppOps legacyOps = new LegacyAppOps();
        if (ClipboardAppOps.check(legacyOps, false, 2000) != 0) throw new AssertionError("Legacy clipboard read unavailable");
        if (ClipboardAppOps.check(legacyOps, true, 2000) != 1) throw new AssertionError("Legacy clipboard write denial lost");
        if (ClipboardAppOps.check(new ModernAppOps(), false, 2000) != 1) throw new AssertionError("Modern clipboard denial lost");
        try { ClipboardAppOps.check(new DeniedAppOps(), false, 2000); throw new AssertionError("AppOps permission denial lost"); }
        catch (SecurityException expected) { }
        try { ClipboardAppOps.check(new InvalidAppOps(), false, 2000); throw new AssertionError("AppOps validation failure lost"); }
        catch (IllegalArgumentException expected) { if (!expected.getMessage().equals("Invalid caller")) throw expected; }
        System.out.println("PASS: API21 clipboard AppOps allow and denial");
    }
}
