# Native callbacks are looked up by literal name and signature in JNI. Keep
# members, not the whole library; these rules must travel with the plugin AAR.
-keepclassmembers class dev.scrcpyconnect.media_codec.MediaCodecPlugin$Session {
    public void onFrame(int, int);
    public long onPcm(java.nio.ByteBuffer);
    public void onPaused(boolean);
    public void onAudioClosed();
    public void onAudioState(java.nio.ByteBuffer);
    public int onHardwareDecoder(java.lang.String);
}
