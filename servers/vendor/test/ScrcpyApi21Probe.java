import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import java.lang.reflect.*;

public final class ScrcpyApi21Probe {
    public static void main(String[] args) throws Exception {
        for (String name : new String[] {"java.util.function.Predicate", "java.util.function.Supplier", "j$.util.function.Predicate$-CC", "com.genymobile.scrcpy.model.Size$$ExternalSyntheticLambda0"}) {
            Class<?> type = Class.forName(name);
            System.out.println("LOADED " + name + " " + type.getClassLoader());
        }
        Class<?> predicate = Class.forName("java.util.function.Predicate");
        Object callback = Proxy.newProxyInstance(predicate.getClassLoader(), new Class<?>[] {predicate}, new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                if (method.getName().equals("test")) return (Integer) values[0] <= 7;
                throw new UnsupportedOperationException(method.getName());
            }
        });
        Class<?> search = Class.forName("com.genymobile.scrcpy.util.BinarySearch");
        Object highest = search.getMethod("findHighestTrue", int.class, int.class, predicate).invoke(null, 1, 10, callback);
        if (!highest.equals(7)) throw new AssertionError(highest);
        System.out.println("BINARY_SEARCH_OK " + highest);
        Class<?> size = Class.forName("com.genymobile.scrcpy.model.Size");
        Class<?> constraints = Class.forName("com.genymobile.scrcpy.video.VideoConstraints");
        boolean checked = false;
        for (MediaCodecInfo codec : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (!codec.isEncoder()) continue;
            for (String mime : codec.getSupportedTypes()) {
                if (!mime.equals("video/avc")) continue;
                MediaCodecInfo.VideoCapabilities caps = codec.getCapabilitiesForType(mime).getVideoCapabilities();
                Object value = constraints.getConstructor(int.class, int.class, MediaCodecInfo.VideoCapabilities.class).newInstance(1280, 8, caps);
                Object result = size.getMethod("constrain", constraints).invoke(size.getConstructor(int.class, int.class).newInstance(1280, 720), value);
                System.out.println("SIZE_CONSTRAIN_OK " + codec.getName() + " " + result);
                checked = true;
            }
        }
        if (!checked) throw new AssertionError("No AVC encoder capabilities");
        System.out.println("PROBE_OK");
    }
}
