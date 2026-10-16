package com.interop.companion;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.media.MediaMetadataRetriever;
import android.media.MediaDataSource;
import android.os.Build;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import android.util.Base64;
import java.io.*;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.json.JSONObject;

/** Isolated, single-request shell process. Never sends original media bytes. */
public final class Thumbnail {
    static final int MAX_JPEG = 256 * 1024;
    static final long MAX_SOURCE = 64L * 1024 * 1024 * 1024;
    static final class Failure extends Exception {
        final String code;
        Failure(String code, String message) { super(message); this.code = code; }
    }
    private static Long nanos(StructStat stat, String field) {
        try {
            Object time = StructStat.class.getField(field).get(stat);
            Field nsec = time.getClass().getField("tv_nsec");
            return nsec.getLong(time);
        } catch (ReflectiveOperationException e) { return null; }
    }
    static JSONObject stamp(StructStat stat) throws Exception {
        Long modified = nanos(stat, "st_mtim"), changed = nanos(stat, "st_ctim");
        return new JSONObject().put("device", Long.toString(stat.st_dev)).put("inode", Long.toString(stat.st_ino))
            .put("mode", stat.st_mode).put("size", stat.st_size).put("modifiedSeconds", stat.st_mtime)
            .put("changedSeconds", stat.st_ctime).put("modifiedNanos", modified == null ? JSONObject.NULL : modified)
            .put("changedNanos", changed == null ? JSONObject.NULL : changed);
    }
    private static void regular(StructStat stat) throws Exception {
        if (!OsConstants.S_ISREG(stat.st_mode)) throw new Failure("not_a_file", "Thumbnail source must be a regular file, without a final symbolic link");
        if (stat.st_size < 0 || stat.st_size > MAX_SOURCE) throw new Failure("media_input_limit", "Media source exceeds the bounded input size");
    }
    private static String validation(StructStat stat) {
        return nanos(stat,"st_mtim") != null && nanos(stat,"st_ctim") != null
            ? "descriptorDeviceInodeSizeModeMtimeCtimeWithNanosecondFields" : "descriptorDeviceInodeSizeModeMtimeCtimeSeconds";
    }
    private static String digest(byte[] bytes) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder text = new StringBuilder(64);
        for (byte value : hash) text.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
        return text.toString();
    }
    private static Bitmap image(FileDescriptor fd, String path, long size, int maxSize, JSONObject result) throws Exception {
        if (size > 256L * 1024 * 1024) throw new Failure("media_input_limit", "Image exceeds the bounded input size");
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFileDescriptor(fd, null, bounds);
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw new Failure("media_decode_failed", "Image header is corrupt or this decoder cannot read it");
        if ((long) bounds.outWidth * bounds.outHeight > 100_000_000L) throw new Failure("media_pixel_limit", "Image dimensions exceed the bounded pixel count");
        Os.lseek(fd, 0, OsConstants.SEEK_SET);
        // The FD constructor asks FileUtils for ActivityThread.currentApplication
        // on Android 12+, which is absent in a shell process. The read-only
        // InputStream API avoids MediaProvider transcoding and keeps this exact FD.
        int orientation;
        try (InputStream input = new BufferedInputStream(new FileInputStream(Os.dup(fd)), 8192)) {
            ExifInterface exif = new ExifInterface(input);
            orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        }
        if (orientation == ExifInterface.ORIENTATION_UNDEFINED) orientation = ExifInterface.ORIENTATION_NORMAL;
        if (orientation < 1 || orientation > 8) throw new Failure("media_orientation_invalid", "Image orientation is invalid");
        Os.lseek(fd, 0, OsConstants.SEEK_SET);
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = 1;
        while (Math.max(bounds.outWidth, bounds.outHeight) / options.inSampleSize > maxSize) options.inSampleSize *= 2;
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        Bitmap decoded = BitmapFactory.decodeFileDescriptor(fd, null, options);
        if (decoded == null) throw new Failure("media_decode_failed", "Image decoder returned no bitmap");
        try {
            if ((long) decoded.getWidth() * decoded.getHeight() > 1_048_576L) throw new Failure("media_pixel_limit", "Decoder did not honor bounded sampling");
            Matrix matrix = new Matrix();
            switch (orientation) {
                case 2: matrix.setScale(-1, 1); break;
                case 3: matrix.setRotate(180); break;
                case 4: matrix.setScale(1, -1); break;
                case 5: matrix.setRotate(90); matrix.postScale(-1, 1); break;
                case 6: matrix.setRotate(90); break;
                case 7: matrix.setRotate(-90); matrix.postScale(-1, 1); break;
                case 8: matrix.setRotate(-90); break;
                default: break;
            }
            Bitmap transformed = Bitmap.createBitmap(decoded, 0, 0, decoded.getWidth(), decoded.getHeight(), matrix, true);
            result.put("orientation", orientation).put("orientationApplied", "imageExif");
            if (transformed != decoded) decoded.recycle();
            return transformed;
        } catch (Exception | Error e) { decoded.recycle(); throw e; }
    }
    private static Bitmap video(FileDescriptor fd, long size, int maxSize, JSONObject result) throws Exception {
        if (Build.VERSION.SDK_INT < 27) throw new Failure("thumbnail_api_pending", "Bounded video frame retrieval on Android below 8.1 has not been implemented; explicitly open the original instead");
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            // Read the exact opened descriptor through the public API. The FD
            // overload invokes ActivityThread-dependent MediaProvider conversion
            // on Android 12+, unavailable in an app_process shell child.
            retriever.setDataSource(new MediaDataSource() {
                @Override public long getSize() { return size; }
                @Override public int readAt(long position, byte[] buffer, int offset, int count) throws IOException {
                    if (position < 0) throw new IOException("Invalid media offset");
                    if (position >= size) return -1;
                    try {
                        int read = Os.pread(fd, buffer, offset, (int)Math.min(count, size - position), position);
                        return read == 0 ? -1 : read;
                    } catch (ErrnoException e) { throw e.rethrowAsIOException(); }
                }
                @Override public void close() { /* outer descriptor owner closes */ }
            });
            String text = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
            int rotation = text == null ? 0 : Integer.parseInt(text);
            if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) throw new Failure("media_orientation_invalid", "Video rotation is invalid");
            // AOSP's retriever already rotates the returned bitmap. Applying
            // the metadata rotation a second time would corrupt orientation.
            Bitmap frame = retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxSize, maxSize);
            if (frame == null) throw new Failure("media_no_frame", "Video contains no retrievable frame, or the device decoder cannot provide one");
            if ((long) frame.getWidth() * frame.getHeight() > 1_048_576L) { frame.recycle(); throw new Failure("media_pixel_limit", "Video decoder did not honor bounded scaling"); }
            result.put("videoRotation", rotation).put("orientationApplied", "platformVideoRotation").put("frameTimeUs", 0);
            return frame;
        } finally { retriever.release(); }
    }
    private static final class OutputLimit extends RuntimeException {}
    private static final class BoundedOutput extends ByteArrayOutputStream {
        @Override public synchronized void write(int b) { if (count == MAX_JPEG) throw new OutputLimit(); super.write(b); }
        @Override public synchronized void write(byte[] bytes, int offset, int length) { if (length > MAX_JPEG - count) throw new OutputLimit(); super.write(bytes, offset, length); }
    }
    static JSONObject execute(JSONObject request) throws Exception {
        String path = request.getString("path");
        if (!path.startsWith("/") || path.length() > 4096 || path.indexOf('\0') >= 0) throw new Failure("invalid_path", "Absolute media path is invalid");
        regular(Os.lstat(path));
        FileDescriptor fd = Os.open(path, OsConstants.O_RDONLY | OsConstants.O_NOFOLLOW | OsConstants.O_CLOEXEC, 0);
        try {
            StructStat before = Os.fstat(fd); regular(before);
            JSONObject source = stamp(before);
            JSONObject result = new JSONObject().put("sourceStamp", source).put("originalSize", before.st_size)
                .put("sourceValidation", validation(before)).put("transformVersion", 1);
            if (!request.getString("command").equals("media.stat")) {
                int maxSize = request.optInt("maxSize", 256);
                if (maxSize < 64 || maxSize > 512) throw new Failure("invalid_argument", "Thumbnail size must be between 64 and 512");
                String kind = request.getString("kind");
                Bitmap bitmap;
                if (kind.equals("image")) bitmap = image(fd, path, before.st_size, maxSize, result);
                else if (kind.equals("video")) bitmap = video(fd, before.st_size, maxSize, result);
                else throw new Failure("invalid_argument", "Thumbnail media kind is invalid");
                Bitmap flat = null;
                try {
                    int width = bitmap.getWidth(), height = bitmap.getHeight();
                    double scale = Math.min(1.0, (double) maxSize / Math.max(width, height));
                    int targetWidth = Math.max(1, (int) Math.round(width * scale)), targetHeight = Math.max(1, (int) Math.round(height * scale));
                    flat = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888);
                    Canvas canvas = new Canvas(flat); canvas.drawColor(Color.WHITE);
                    canvas.drawBitmap(bitmap, null, new android.graphics.Rect(0, 0, targetWidth, targetHeight), new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG));
                    BoundedOutput encoded = new BoundedOutput();
                    if (!flat.compress(Bitmap.CompressFormat.JPEG, 82, encoded)) throw new Failure("media_encode_failed", "JPEG compression failed");
                    byte[] jpeg = encoded.toByteArray();
                    result.put("width", targetWidth).put("height", targetHeight).put("mime", "image/jpeg").put("thumbnail", true)
                        .put("jpegBytes", jpeg.length).put("sha256", digest(jpeg)).put("data", Base64.encodeToString(jpeg, Base64.NO_WRAP));
                } catch (OutputLimit e) { throw new Failure("thumbnail_output_limit", "Encoded thumbnail exceeds the output bound"); }
                finally { if (flat != null) flat.recycle(); bitmap.recycle(); }
            }
            if (!source.toString().equals(stamp(Os.fstat(fd)).toString()) || !source.toString().equals(stamp(Os.lstat(path)).toString())) {
                throw new Failure("source_changed", "Media source changed while generating or checking its thumbnail");
            }
            return result;
        } finally { Os.close(fd); }
    }
    public static void main(String[] ignored) {
        // Kill only this process, not a retained numeric child PID. Both the
        // deadline and the stdin-EOF monitor remain runnable during native decode.
        Thread deadline = new Thread(() -> { try { Thread.sleep(8000); } catch (InterruptedException ignoredSleep) {} android.os.Process.killProcess(android.os.Process.myPid()); }, "interop-media-deadline");
        deadline.setDaemon(true); deadline.start();
        JSONObject response = new JSONObject();
        try {
            ByteArrayOutputStream line = new ByteArrayOutputStream();
            for (int value; (value = System.in.read()) != -1 && value != '\n';) {
                if (line.size() >= 16_384) throw new Failure("invalid_argument", "Thumbnail request exceeds the input bound");
                line.write(value);
            }
            Thread parent = new Thread(() -> { try { while (System.in.read() != -1) {} } catch (IOException ignoredRead) {} android.os.Process.killProcess(android.os.Process.myPid()); }, "interop-media-parent");
            parent.setDaemon(true); parent.start();
            response.put("result", execute(new JSONObject(new String(line.toByteArray(), StandardCharsets.UTF_8))));
        } catch (Throwable e) {
            String code = e instanceof Failure ? ((Failure)e).code : e instanceof OutOfMemoryError ? "thumbnail_memory_limit"
                : e instanceof ErrnoException && (((ErrnoException)e).errno == OsConstants.EACCES || ((ErrnoException)e).errno == OsConstants.EPERM) ? "permission_denied"
                : e instanceof ErrnoException && ((ErrnoException)e).errno == OsConstants.ENOENT ? "not_found" : "media_decode_failed";
            try { response.put("error", new JSONObject().put("code", code).put("message", e instanceof Failure ? e.getMessage() : "Media decoder or source access failed (" + e.getClass().getSimpleName() + ")")); }
            catch (Exception ignoredError) { System.exit(2); }
        }
        System.out.println(response.toString()); System.out.flush(); System.exit(0);
    }
}
