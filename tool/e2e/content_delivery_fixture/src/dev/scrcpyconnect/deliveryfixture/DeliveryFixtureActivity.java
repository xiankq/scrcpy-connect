package dev.scrcpyconnect.deliveryfixture;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** A separate, test-only recipient for a real system Sharesheet delivery. */
public final class DeliveryFixtureActivity extends Activity {
    private static final int MAX_BYTES = 2 * 1024 * 1024;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setTextSize(20);
        view.setPadding(32, 64, 32, 32);
        view.setText("Verifying received content…");
        setContentView(view);

        Intent intent = getIntent();
        new Thread(() -> verify(intent, view), "delivery-verifier").start();
    }

    private void verify(Intent intent, TextView view) {
        JSONObject receipt = new JSONObject();
        String displayName = null;
        long bytesRead = 0;
        String outcome;
        try {
            receipt.put("status", "processing");
            receipt.put("success", false);
            receipt.put("receivedAtEpochMillis", System.currentTimeMillis());
            receipt.put("action", value(intent == null ? null : intent.getAction()));
            receipt.put("intentMime", value(intent == null ? null : intent.getType()));
            receipt.put("resolvedMime", JSONObject.NULL);
            receipt.put("displayName", JSONObject.NULL);
            receipt.put("bytes", 0);
            receipt.put("sha256", JSONObject.NULL);
            receipt.put("uriScheme", JSONObject.NULL);
            receipt.put("readGrant", intent != null &&
                    (intent.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0);
            receipt.put("error", JSONObject.NULL);
            writeReceipt(receipt);

            if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) {
                throw new VerificationFailure("unsupported_action");
            }
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri.class);
            if (uri == null) {
                throw new VerificationFailure("missing_stream_uri");
            }
            receipt.put("uriScheme", value(uri.getScheme()));
            if (!"content".equals(uri.getScheme())) {
                throw new VerificationFailure("stream_uri_must_use_content_scheme");
            }
            if (!receipt.getBoolean("readGrant")) {
                throw new VerificationFailure("missing_intent_read_grant");
            }

            String resolvedMime = getContentResolver().getType(uri);
            receipt.put("resolvedMime", value(resolvedMime));
            try (Cursor cursor = getContentResolver().query(uri,
                    new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
                if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) {
                    displayName = cursor.getString(0);
                }
            }
            receipt.put("displayName", value(displayName));

            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = getContentResolver().openInputStream(uri)) {
                if (input == null) {
                    throw new VerificationFailure("provider_returned_no_stream");
                }
                byte[] buffer = new byte[16 * 1024];
                while (bytesRead < MAX_BYTES) {
                    int count = input.read(buffer, 0,
                            (int) Math.min(buffer.length, MAX_BYTES - bytesRead));
                    if (count < 0) {
                        receipt.put("sha256", hex(digest.digest()));
                        receipt.put("success", true);
                        break;
                    }
                    if (count == 0) {
                        throw new VerificationFailure("provider_returned_empty_read");
                    }
                    digest.update(buffer, 0, count);
                    bytesRead += count;
                }
                // Do not consume byte MAX_BYTES + 1 just to test for EOF. A stream
                // that reaches the cap is conservatively rejected, even at exactly 2 MiB.
                if (!receipt.getBoolean("success")) {
                    throw new VerificationFailure("read_limit_reached_2_mib");
                }
            }
            receipt.put("status", "success");
            outcome = "SUCCESS";
        } catch (Exception error) {
            outcome = "FAILED";
            try {
                receipt.put("status", "error");
                receipt.put("success", false);
                receipt.put("sha256", JSONObject.NULL);
                receipt.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
            } catch (Exception ignored) {
                // JSONObject values above are all supported types.
            }
        }
        try {
            receipt.put("bytes", bytesRead);
            writeReceipt(receipt);
        } catch (Exception error) {
            outcome = "FAILED (could not write receipt): " + error.getMessage();
        }
        String result = outcome + "\n" + (displayName == null ? "(no display name)" : displayName);
        runOnUiThread(() -> view.setText(result));
    }

    private void writeReceipt(JSONObject receipt) throws Exception {
        File temporary = new File(getFilesDir(), "receipt.json.tmp");
        try (FileOutputStream output = new FileOutputStream(temporary)) {
            output.write((receipt.toString(2) + "\n").getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
        if (!temporary.renameTo(new File(getFilesDir(), "receipt.json"))) {
            throw new java.io.IOException("cannot replace receipt.json");
        }
    }

    private static Object value(String value) {
        return value == null ? JSONObject.NULL : value;
    }

    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            result.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        }
        return result.toString();
    }

    private static final class VerificationFailure extends Exception {
        VerificationFailure(String message) {
            super(message);
        }
    }
}
