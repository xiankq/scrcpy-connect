package com.interop.companion;

import java.io.*;
import java.util.concurrent.TimeUnit;

/** 主机契约测试：API21 Process 接口仅有 exitValue/destroy。 */
public final class CompatibilityTest {
    public static final class Users {
        static Object current = 10;
        static boolean denied;
        static int queries;
        public static Object getCurrentUser() {
            queries++;
            if (denied) throw new SecurityException("current user denied");
            return current;
        }
    }
    private static void userFailure(CurrentUser user, String code) throws Exception {
        try { user.require(); throw new AssertionError("Unverified user accepted"); }
        catch (Main.Failure expected) {
            if (!expected.code.equals(code)) throw new AssertionError("Unexpected user failure: " + expected.code);
        }
    }
    private static void userBoundary(Main companion, String method, String code) throws Exception {
        java.lang.reflect.Method boundary = Main.class.getDeclaredMethod(method);
        Object[] arguments = new Object[0];
        boundary.setAccessible(true);
        try { boundary.invoke(companion, arguments); throw new AssertionError("Old-user content accepted by " + method); }
        catch (java.lang.reflect.InvocationTargetException failure) {
            if (!(failure.getCause() instanceof Main.Failure) || !((Main.Failure) failure.getCause()).code.equals(code)) throw failure;
        }
    }
    private static void currentUser() throws Exception {
        CurrentUser session = new CurrentUser(Users.class);
        Main companion = new Main(session);
        if (Users.queries != 0) throw new AssertionError("User-independent startup resolved a user");
        Users.denied = true;
        userFailure(session, "user_unavailable");
        try { session.owner(); throw new AssertionError("Failed lookup guessed an owner"); }
        catch (Main.Failure expected) { }
        Users.denied = false;
        for (Object invalid : new Object[]{null, -1, -2, "10"}) {
            Users.current = invalid;
            userFailure(session, "user_unavailable");
        }
        userFailure(new CurrentUser(Object.class), "user_unavailable");
        Users.current = 10;
        if (session.require() != 10 || session.owner() != 10 || session.require() != 10)
            throw new AssertionError("Verified current user did not bind");
        Users.current = 11;
        userFailure(session, "user_changed");
        java.lang.reflect.Field enabled = Main.class.getDeclaredField("observationEnabled");
        enabled.setAccessible(true);
        enabled.setBoolean(companion, true);
        for (String boundary : new String[]{"notificationSnapshot", "callSnapshot", "openPhoneApp"})
            userBoundary(companion, boundary, "user_changed");
        int queries = Users.queries;
        if (session.owner() != 10 || Users.queries != queries)
            throw new AssertionError("Cleanup lost the original listener owner");
        Users.denied = true;
        userFailure(session, "user_unavailable");
        for (String boundary : new String[]{"notificationSnapshot", "callSnapshot", "openPhoneApp"})
            userBoundary(companion, boundary, "user_unavailable");
        if (session.owner() != 10) throw new AssertionError("Lookup failure replaced the bound user");
        Users.denied = false;
        Users.current = 0;
        if (new CurrentUser(Users.class).require() != 0)
            throw new AssertionError("An actually verified user zero was rejected");
        System.out.println("PASS: lazy user binding, lookup failures, user switch and original-owner cleanup");
    }
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
        currentUser();
        if (!Apps.applicationTask(true, 1, 1, 10, 10)) throw new AssertionError("Running standard task missing");
        if (Apps.applicationTask(false, 1, 1, 10, 10)
            || Apps.applicationTask(true, 0, 1, 10, 10)
            || Apps.applicationTask(true, 1, 1, 0, 10)) throw new AssertionError("Inactive or other-user task leaked");
        for (int type : new int[]{0, 2, 3, 4, 5}) {
            if (Apps.applicationTask(true, 1, type, 10, 10)) throw new AssertionError("Non-application task leaked");
        }
        System.out.println("PASS: application task type, lifecycle and user filtering");
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

    }
}
