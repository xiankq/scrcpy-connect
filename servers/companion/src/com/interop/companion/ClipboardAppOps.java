package com.interop.companion;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** 使用真实 shell 归因预检 AppOps 权限。 */
final class ClipboardAppOps {
    private static Object invoke(Object manager, Method method, Object operation, int uid) throws Exception {
        method.setAccessible(true);
        try { return method.invoke(manager, operation, uid, "com.android.shell"); }
        catch (InvocationTargetException failure) {
            if (failure.getCause() instanceof Exception) throw (Exception) failure.getCause();
            throw failure;
        }
    }
    static int check(Object manager, boolean writing, int uid) throws Exception {
        String operation = writing ? "android:write_clipboard" : "android:read_clipboard";
        Method modern = null;
        try { modern = manager.getClass().getMethod("checkOpNoThrow", String.class, int.class, String.class); }
        catch (NoSuchMethodException absent) { /* Known old integer boundary below. */ }
        if (modern != null) {
            try { return (Integer) invoke(manager, modern, operation, uid); }
            catch (IllegalArgumentException unsupported) {
                // AOSP21 有整数剪贴板操作码但没有字符串映射；仅此精确映射失败允许旧调用，权限拒绝、SecurityException 及其他错误均保留。
                //
                //
                if (!("Unknown operation string: " + operation).equals(unsupported.getMessage())) throw unsupported;
            }
        }
        int expected = writing ? 30 : 29;
        String field = writing ? "OP_WRITE_CLIPBOARD" : "OP_READ_CLIPBOARD";
        int actual = manager.getClass().getField(field).getInt(null);
        if (actual != expected) throw new NoSuchMethodException("Unsupported legacy clipboard AppOp value");
        Method legacy = manager.getClass().getMethod("checkOpNoThrow", int.class, int.class, String.class);
        return (Integer) invoke(manager, legacy, actual, uid);
    }
}
