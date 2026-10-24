//! 独立 scrcpy 宿主同时提供配套 ADB 能力；所有句柄留在本动态库内。
mod frb_generated;

#[flutter_rust_bridge::frb(init)]
pub fn init_scrcpy() {
    flutter_rust_bridge::setup_default_user_utils();
}
