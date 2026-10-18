package android.media;

/** Only the capability query used by the real SurfaceEncoder is modeled. */
public final class MediaCodecInfo {
    public CodecCapabilities getCapabilitiesForType(String mime) {
        return new CodecCapabilities();
    }

    public static final class CodecCapabilities {
        public static final int COLOR_FormatSurface = 0x7f000789;

        public VideoCapabilities getVideoCapabilities() {
            return new VideoCapabilities();
        }
    }

    public static final class VideoCapabilities {
        public int getWidthAlignment() {
            return 2;
        }

        public int getHeightAlignment() {
            return 2;
        }
    }
}
