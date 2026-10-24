package dev.scrcpyconnect.sharefixture;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.util.Base64;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

/** 仅测试使用且不导出的 provider，访问仅依赖系统 URI 读取授权。 */
public final class FixtureProvider extends ContentProvider {
    private static final AtomicInteger opens = new AtomicInteger();
    private static final byte[] PNG = Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSb8AAAAASUVORK5CYII=", Base64.DEFAULT);
    private static final byte[] TEXT = "Connect incoming share fixture\n中文与空格\n".getBytes(StandardCharsets.UTF_8);
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return uri.getPath().contains("image") ? "image/png" : "text/plain"; }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        MatrixCursor cursor = new MatrixCursor(new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE });
        String path = uri.getPath();
        if (path.contains("stats")) cursor.addRow(new Object[] { "open-count", opens.get() });
        else {
            // 避免 Java 数值条件表达式对未知的 null 大小执行拆箱。
            Long size = null;
            if (path.contains("oversize")) size = 513L * 1024 * 1024;
            else if (!path.contains("slow")) size = (long) (path.contains("image") ? PNG.length : TEXT.length);
            cursor.addRow(new Object[] { path.contains("image") ? "共享 图片.png" : "共享 文本.txt", size });
        }
        return cursor;
    }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("read-only fixture");
        opens.incrementAndGet();
        try {
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
            Thread writer = new Thread(() -> {
                try (ParcelFileDescriptor.AutoCloseOutputStream output = new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])) {
                    if (uri.getPath().contains("slow")) {
                        for (int i = 0; i < 180; ++i) { output.write('s'); output.flush(); Thread.sleep(1000); }
                    } else output.write(uri.getPath().contains("image") ? PNG : TEXT);
                } catch (IOException ignored) { /* Receiver cancel closes its end. */ }
                  catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
            }, "share-fixture-pipe");
            writer.setDaemon(true); writer.start(); return pipe[0];
        } catch (IOException error) { throw new FileNotFoundException(error.toString()); }
    }
    @Override public AssetFileDescriptor openAssetFile(Uri uri, String mode) throws FileNotFoundException {
        if (uri.getPath().contains("oversize")) {
            // 提供真实可读句柄，使元数据由接收方准入检查拒绝，而非因夹具异常失败。
            //
            return new AssetFileDescriptor(openFile(uri, mode), 0, 513L * 1024 * 1024);
        }
        return super.openAssetFile(uri, mode);
    }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
