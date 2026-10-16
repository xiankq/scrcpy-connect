package com.interop.companion;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

/** One decoder process plus one waiting job; independent of Binder callbacks. */
final class MediaJobs implements AutoCloseable {
    interface Reply { void send(JSONObject value) throws Exception; }
    private final Reply reply;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, new ArrayBlockingQueue<Runnable>(1));
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
    private final Map<String, Job> active = new ConcurrentHashMap<>();
    private final Set<String> seen = new HashSet<>();
    private final AtomicBoolean closed = new AtomicBoolean();
    MediaJobs(Reply reply) { this.reply = reply; }
    private JSONObject failure(String code, String message) throws Exception { return new JSONObject().put("code", code).put("message", message); }
    private void respond(JSONObject request, JSONObject result, JSONObject error) throws Exception {
        JSONObject response = new JSONObject().put("requestId", request.getString("requestId"));
        response.put(error == null ? "result" : "error", error == null ? result : error); reply.send(response);
    }
    void accept(JSONObject request) throws Exception {
        String operation = request.optString("operationId");
        String owner = request.optString("ownerOperationId", operation);
        if (!owner.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) {
            respond(request, null, failure("invalid_argument", "Media owner identity is invalid")); return;
        }
        if (!operation.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) {
            respond(request, null, failure("invalid_argument", "Media operation identity is invalid")); return;
        }
        String command = request.getString("command");
        if (command.equals("media.shutdown")) {
            respond(request, new JSONObject().put("reaped", shutdown()), null); return;
        }
        if (command.equals("media.thumbnail.cancel")) {
            Job job = active.get(operation);
            boolean stopped = job == null || job.cancel("cancelled");
            synchronized (seen) { if (seen.size() < 65536) seen.add(operation); }
            respond(request, new JSONObject().put("cancelRequested", true).put("reaped", stopped), null); return;
        }
        if (!command.equals("media.thumbnail") && !command.equals("media.stat")) {
            respond(request, null, failure("invalid_command", "Unknown media command")); return;
        }
        if (android.os.Build.VERSION.SDK_INT < 26) {
            respond(request, null, failure("thumbnail_api_pending", "Bounded isolated media process lifecycle on Android below 8.0 has not been implemented")); return;
        }
        synchronized (seen) {
            if (seen.contains(operation)) { respond(request, null, failure("operation_reused", "Media operation has already ended or been cancelled")); return; }
            if (seen.size() == 65536) { respond(request, null, failure("operation_limit", "Media operation identity limit reached; reconnect the companion")); return; }
            seen.add(operation);
        }
        if (closed.get()) { respond(request, null, failure("cancelled", "Companion is closing")); return; }
        Job job = new Job(operation, request); active.put(operation, job);
        try { worker.execute(job); }
        catch (RejectedExecutionException e) { active.remove(operation, job); job.finish(null, failure("busy", "The bounded media worker is busy")); }
    }
    private final class Job implements Runnable {
        final String operation;
        final JSONObject request;
        final AtomicBoolean finished = new AtomicBoolean();
        volatile java.lang.Process process;
        volatile String cancelled;
        Job(String operation, JSONObject request) { this.operation = operation; this.request = request; }
        void finish(JSONObject result, JSONObject error) {
            if (!finished.compareAndSet(false, true)) return;
            java.lang.Process child = process;
            if (child == null || !child.isAlive()) active.remove(operation, this);
            try { respond(request, result, error); } catch (Exception ignored) {}
        }
        boolean cancel(String code) {
            java.lang.Process child;
            synchronized (this) { cancelled = code; child = process; }
            worker.remove(this);
            boolean reaped = child == null || terminate(child);
            try { finish(null, failure(reaped ? code : "media_cleanup_unknown", reaped ? "Media operation stopped" : "Decoder termination has not been confirmed; no thumbnail was published")); } catch (Exception ignored) {}
            return reaped;
        }
        @Override public void run() {
            ScheduledFuture<?> deadline = null;
            JSONObject result = null, error = null;
            try {
                synchronized (this) {
                    if (cancelled != null || closed.get()) throw new Thumbnail.Failure("cancelled", "Media operation was cancelled");
                    process = new ProcessBuilder("/system/bin/app_process", "/", "--nice-name=" +
                        (request.getString("command").equals("media.stat") ? "interop-stat-" : "interop-thumb-") + request.optString("ownerOperationId", operation),
                        "com.interop.companion.Thumbnail").start();
                }
                java.lang.Process child = process;
                Thread stderr = new Thread(() -> {
                    // Drain diagnostics without storing or logging source paths/content.
                    try { byte[] buffer = new byte[2048]; while (child.getErrorStream().read(buffer) != -1) {} } catch (IOException ignored) {}
                }, "interop-media-stderr"); stderr.setDaemon(true); stderr.start();
                deadline = timer.schedule(() -> cancel("media_timeout"), 10, TimeUnit.SECONDS);
                byte[] input = (request.toString() + "\n").getBytes(StandardCharsets.UTF_8);
                if (input.length > 16384) throw new Thumbnail.Failure("invalid_argument", "Media request exceeds the input bound");
                child.getOutputStream().write(input); child.getOutputStream().flush();
                // Keep stdin open: EOF asks the child's independent monitor to
                // SIGKILL itself. Native decode does not block that monitor.
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                for (int value; (value = child.getInputStream().read()) != -1 && value != '\n';) {
                    if (output.size() >= 384 * 1024) throw new Thumbnail.Failure("thumbnail_output_limit", "Decoder response exceeds the output bound");
                    output.write(value);
                }
                if (!child.waitFor(2, TimeUnit.SECONDS)) throw new Thumbnail.Failure("media_timeout", "Decoder did not exit after its response");
                if (child.exitValue() != 0 || output.size() == 0) throw new Thumbnail.Failure("media_decode_failed", "Isolated media process exited without a valid result");
                JSONObject response = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
                result = response.optJSONObject("result"); error = response.optJSONObject("error");
                if (result == null && error == null) throw new Thumbnail.Failure("media_decode_failed", "Decoder response is invalid");
            } catch (Exception e) {
                try { error = failure(e instanceof Thumbnail.Failure ? ((Thumbnail.Failure)e).code : "media_decode_failed", e instanceof Thumbnail.Failure ? e.getMessage() : "Isolated decoder failed"); } catch (Exception ignored) {}
            } finally {
                if (deadline != null) deadline.cancel(false);
                java.lang.Process child = process;
                boolean reaped = child == null || terminate(child);
                if (!reaped) {
                    try { error = failure("media_cleanup_unknown", "Decoder termination has not been confirmed; no thumbnail was published"); } catch (Exception ignored) {}
                }
                if (reaped) active.remove(operation, this);
                if (cancelled != null && reaped) { try { error = failure(cancelled, "Media operation stopped"); } catch (Exception ignored) {} }
                finish(error == null ? result : null, error);
            }
        }
    }
    private static boolean terminate(java.lang.Process child) {
        try {
            try { child.exitValue(); return true; } catch (IllegalThreadStateException alive) {}
            try { child.getOutputStream().close(); } catch (IOException ignored) {}
            if (child.waitFor(2, TimeUnit.SECONDS)) return true;
            // Owned Process fallback, never an arbitrary numeric PID. On AOSP
            // this is SIGTERM; the child's own deadline provides SIGKILL.
            child.destroy();
            return child.waitFor(2, TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); return false; }
    }
    @Override public void close() { shutdown(); }
    private boolean shutdown() {
        closed.set(true);
        boolean reaped = true;
        for (Job job : active.values()) if (!job.cancel("cancelled")) reaped = false;
        worker.shutdownNow(); timer.shutdownNow();
        return reaped;
    }
}
