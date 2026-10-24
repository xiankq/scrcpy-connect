package com.interop.companion;

import java.util.concurrent.TimeUnit;

/** 对本协同助手拥有的进程进行有界等待。 */
final class Processes {
    static boolean alive(Process process) {
        try { process.exitValue(); return false; }
        catch (IllegalThreadStateException running) { return true; }
    }
    static boolean await(Process process, long milliseconds) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(milliseconds);
        while (alive(process)) {
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) return false;
            TimeUnit.NANOSECONDS.sleep(Math.min(remaining, TimeUnit.MILLISECONDS.toNanos(10)));
        }
        return true;
    }
}
