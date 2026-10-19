package com.interop.companion;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** The read-only call-state Binder boundary; no accept/end-call methods. */
final class CallServices {
    private static final String PACKAGE = "com.android.shell";
    private static Method method(Object service, String name, Object token, Class<?>... signature) {
        for (Method candidate : service.getClass().getMethods()) {
            if (!candidate.getName().equals(name)) continue;
            Class<?>[] actual = candidate.getParameterTypes();
            if (actual.length != signature.length) continue;
            boolean matches = true;
            for (int i = 0; i < actual.length; i++) {
                if (signature[i] == null ? token == null || !actual[i].isInstance(token) : actual[i] != signature[i]) matches = false;
            }
            if (matches) return candidate;
        }
        return null;
    }
    private static Object invoke(Object service, Method method, Object... arguments) throws Exception {
        method.setAccessible(true);
        try { return method.invoke(service, arguments); }
        catch (InvocationTargetException failure) {
            if (failure.getCause() instanceof Exception) throw (Exception) failure.getCause();
            throw failure;
        }
    }
    static void listen(Object registry, Object token, boolean enabled) throws Exception {
        Method selected = method(registry, "listenWithEventList", token, boolean.class, boolean.class, int.class,
            String.class, String.class, null, int[].class, boolean.class);
        if (selected != null) {
            invoke(registry, selected, true, true, Integer.MAX_VALUE, PACKAGE, null, token, enabled ? new int[]{6} : new int[0], enabled);
            return;
        }
        selected = method(registry, "listenForSubscriber", token, int.class, String.class, String.class, null, int.class, boolean.class);
        if (selected != null) {
            invoke(registry, selected, Integer.MAX_VALUE, PACKAGE, null, token, enabled ? 32 : 0, enabled);
            return;
        }
        for (Class<?> subscription : new Class<?>[]{int.class, long.class}) {
            selected = method(registry, "listenForSubscriber", token, subscription, String.class, null, int.class, boolean.class);
            if (selected == null) continue;
            Object id;
            if (subscription == long.class) id = Long.valueOf(Long.MAX_VALUE);
            else id = Integer.valueOf(Integer.MAX_VALUE);
            invoke(registry, selected, id, PACKAGE, token, enabled ? 32 : 0, enabled);
            return;
        }
        throw new NoSuchMethodException("Unsupported read-only phone listener signature");
    }
    static int state(Object telecom) throws Exception {
        Method selected = method(telecom, "getCallStateUsingPackage", null, String.class, String.class);
        if (selected != null) return (Integer) invoke(telecom, selected, PACKAGE, null);
        selected = method(telecom, "getCallState", null);
        if (selected != null) return (Integer) invoke(telecom, selected);
        throw new NoSuchMethodException("Unsupported read-only call-state signature");
    }
    static Method systemUiMethod(Object telecom) {
        if (telecom == null) return null;
        for (Class<?>[] signature : new Class<?>[][]{
                {boolean.class, String.class, String.class}, {boolean.class, String.class}, {boolean.class}}) {
            Method selected = method(telecom, "showInCallScreen", null, signature);
            if (selected != null) return selected;
        }
        return null;
    }
    static void openSystemUi(Object telecom) throws Exception {
        Method selected = systemUiMethod(telecom);
        if (selected == null) throw new NoSuchMethodException("Unsupported system call UI signature");
        int count = selected.getParameterTypes().length;
        if (count == 3) invoke(telecom, selected, false, PACKAGE, null);
        else if (count == 2) invoke(telecom, selected, false, PACKAGE);
        else invoke(telecom, selected, false);
    }
}
