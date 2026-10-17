package dev.scrcpyconnect.notificationfixture;

import android.content.Context;
import android.util.AtomicFile;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

final class FixtureStore {
    static final String PREFIX = "dev.scrcpyconnect.notificationfixture.";
    static final String RESULT_KEY = "original-result-key";

    static String runId(String value) {
        if (value == null || !value.matches("[A-Za-z0-9_-]{1,80}")) {
            throw new IllegalArgumentException("A bounded explicit runId is required");
        }
        return value;
    }

    static String tag(String runId) {
        return "notification-fixture-" + runId(runId);
    }

    static AtomicFile file(Context context, String directory, String runId) throws Exception {
        File parent = new File(context.getFilesDir(), directory);
        if (!parent.isDirectory() && !parent.mkdirs()) {
            throw new IllegalStateException("Cannot create fixture storage");
        }
        return new AtomicFile(new File(parent, runId(runId) + ".json"));
    }

    static JSONObject read(AtomicFile file) throws Exception {
        return new JSONObject(new String(file.readFully(), StandardCharsets.UTF_8));
    }

    static void write(AtomicFile file, JSONObject value) throws Exception {
        FileOutputStream output = null;
        try {
            output = file.startWrite();
            output.write(value.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(output);
        } catch (Exception error) {
            if (output != null) file.failWrite(output);
            throw error;
        }
    }
}
