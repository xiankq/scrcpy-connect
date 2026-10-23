package com.interop.companion;

import java.lang.reflect.InvocationTargetException;

/** Lazily binds user-dependent work; cleanup retains the original listener owner. */
final class CurrentUser {
    private final Class<?> manager;
    private Integer owner;

    CurrentUser() { this(null); }
    CurrentUser(Class<?> manager) { this.manager = manager; }

    int require() throws Main.Failure {
        final int current;
        try {
            Class<?> api = manager == null ? Class.forName("android.app.ActivityManager") : manager;
            Object value = api.getMethod("getCurrentUser").invoke(null);
            if (!(value instanceof Integer) || (Integer) value < 0)
                throw new IllegalStateException("Current user is not a concrete user ID");
            current = (Integer) value;
        } catch (Exception failure) {
            Throwable cause = failure instanceof InvocationTargetException ? failure.getCause() : failure;
            Main.Failure unavailable = new Main.Failure("user_unavailable", "The current Android user could not be verified");
            unavailable.initCause(cause);
            throw unavailable;
        }
        if (owner != null && owner != current)
            throw new Main.Failure("user_changed", "The current Android user changed; reconnect before continuing user-dependent work");
        owner = current;
        return current;
    }

    int owner() throws Main.Failure {
        if (owner == null) throw new Main.Failure("user_unavailable", "No Android user has been bound");
        return owner;
    }
}
