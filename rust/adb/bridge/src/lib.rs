//! 独立 ADB SDK 的唯一 FRB 动态库入口。
mod frb_generated;

#[flutter_rust_bridge::frb(init)]
pub fn init_adb() {
    flutter_rust_bridge::setup_default_user_utils();
}
