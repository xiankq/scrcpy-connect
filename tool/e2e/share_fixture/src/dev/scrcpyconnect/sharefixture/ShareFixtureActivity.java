package dev.scrcpyconnect.sharefixture;

import android.app.Activity;
import android.content.ClipData;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.ArrayList;

/** A real external sharing app. No product backdoor, package privileges or ADB dependency. */
public final class ShareFixtureActivity extends Activity {
    private static final String AUTHORITY = "dev.scrcpyconnect.sharefixture.content";
    private TextView status;
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout column = new LinearLayout(this); column.setOrientation(LinearLayout.VERTICAL);
        status = new TextView(this); status.setText("Choose an external share fixture"); column.addView(status);
        for (String mode : new String[] { "text", "image", "multi", "alias", "no-grant", "self-sentinel", "file-uri", "too-many", "oversize", "slow" }) {
            Button button = new Button(this); button.setText(mode); button.setOnClickListener(view -> send(mode)); column.addView(button);
        }
        setContentView(column);
        String mode = getIntent().getStringExtra("mode"); if (mode != null) send(mode);
    }
    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String mode = intent.getStringExtra("mode"); if (mode != null) send(mode);
    }
    private void send(String mode) {
        Intent share = new Intent("multi".equals(mode) || "too-many".equals(mode) ? Intent.ACTION_SEND_MULTIPLE : Intent.ACTION_SEND);
        share.setComponent(new ComponentName("dev.scrcpyconnect.scrcpy_connect", "dev.scrcpyconnect.scrcpy_connect.MainActivity"));
        share.setType("image".equals(mode) ? "image/png" : "text/plain");
        if ("text".equals(mode)) share.putExtra(Intent.EXTRA_TEXT, "Connect external text fixture 中文");
        else {
            ArrayList<Uri> uris = new ArrayList<>();
            int count = "too-many".equals(mode) ? 33 : "multi".equals(mode) ? 2 : 1;
            for (int i = 0; i < count; ++i) {
                String path = "image".equals(mode) || ("multi".equals(mode) && i == 1) ? "image.png" : mode + "-" + i + ".txt";
                Uri uri = Uri.parse("content://" + ("alias".equals(mode) ? "dev.scrcpyconnect.sharefixture.alias" : AUTHORITY) + "/" + path);
                if ("self-sentinel".equals(mode)) uri = Uri.parse("content://dev.scrcpyconnect.scrcpy_connect.fileProvider.com.crazecoder.openfile/media/share-trust-sentinel.txt");
                if ("file-uri".equals(mode)) uri = Uri.parse("file:///does-not-exist/share-fixture-sentinel.txt");
                uris.add(uri);
            }
            if (share.getAction().equals(Intent.ACTION_SEND_MULTIPLE)) share.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
            else share.putExtra(Intent.EXTRA_STREAM, uris.get(0));
            // ACTION_SEND auto-migrates EXTRA_STREAM and adds a read grant if
            // ClipData is absent. Supply it explicitly to preserve negative
            // no-grant/own-provider cases through Intent preparation.
            ClipData clip = ClipData.newRawUri("fixture", uris.get(0));
            for (int i = 1; i < uris.size(); ++i) clip.addItem(new ClipData.Item(uris.get(i)));
            share.setClipData(clip);
            if (!"no-grant".equals(mode) && !"self-sentinel".equals(mode) && !"file-uri".equals(mode)) {
                share.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
        }
        try { startActivity(share); status.setText("Sent " + mode); }
        catch (RuntimeException error) { status.setText("OS rejected " + mode + ": " + error.getClass().getSimpleName()); }
    }
}
