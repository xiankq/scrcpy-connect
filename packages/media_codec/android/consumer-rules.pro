# JNI 按字面名称与签名查找原生回调；只保留对应成员，不保留整个库。
# 这些规则必须随插件 AAR 分发。
-keepclassmembers class dev.scrcpyconnect.media_codec.MediaCodecPlugin$Session {
    public void onFrame(int, int);
    public long onPcm(java.nio.ByteBuffer);
    public void onPaused(boolean);
    public void onAudioClosed();
    public void onAudioState(java.nio.ByteBuffer);
    public int onHardwareDecoder(java.lang.String);
}
