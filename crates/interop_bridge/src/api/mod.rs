//! Command boundary. Long-lived connections and activities belong to the Rust runtime.
use interop_core::Runtime;
use serde_json::{Value, json};
use std::sync::{Arc, OnceLock};

static RUNTIME: OnceLock<Arc<Runtime>> = OnceLock::new();
static EXECUTOR: OnceLock<tokio::runtime::Handle> = OnceLock::new();

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    log::set_max_level(log::LevelFilter::Info);
}

pub async fn initialize(data_directory: String) -> Result<(), String> {
    if RUNTIME.get().is_some() {
        return Ok(());
    }
    let runtime = Runtime::initialize(data_directory)
        .await
        .map_err(|e| e.to_string())?;
    let _ = EXECUTOR.set(tokio::runtime::Handle::current());
    RUNTIME
        .set(runtime)
        .map_err(|_| "Runtime was initialized concurrently".to_owned())
}

/// Android's foreground notification can stop connections while Dart is paused.
/// It uses the same runtime, so explicit Stop also disables automatic reconnect.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_scrcpyconnect_scrcpy_1connect_NativeCore_stopAll(
    _env: *mut std::ffi::c_void,
    _receiver: *mut std::ffi::c_void,
) -> bool {
    let (Some(runtime), Some(executor)) = (RUNTIME.get(), EXECUTOR.get()) else {
        return false;
    };
    let runtime = runtime.clone();
    executor.spawn(async move {
        runtime.stop_all().await;
    });
    true
}

pub async fn invoke(request_json: String) -> String {
    let result = async {
        if request_json.len() > 1_048_576 {
            return Err(interop_core::CoreError::new(
                "request_limit",
                "操作内容过长。",
            ));
        }
        let request: Value = serde_json::from_str(&request_json)?;
        let command = request["command"]
            .as_str()
            .ok_or_else(|| interop_core::CoreError::new("invalid_argument", "缺少操作名称。"))?;
        let runtime = RUNTIME.get().ok_or_else(|| {
            interop_core::CoreError::new("not_initialized", "互联核心尚未初始化。")
        })?;
        runtime
            .invoke(
                command,
                request.get("params").cloned().unwrap_or_else(|| json!({})),
            )
            .await
    }
    .await;
    match result {
        Ok(data)=>json!({"ok":true,"data":data}),
        Err(error)=>json!({"ok":false,"error":{"code":error.code,"message":error.message,"details":error.details}}),
    }.to_string()
}

pub async fn events(sink: crate::frb_generated::StreamSink<String>) -> Result<(), String> {
    let runtime = RUNTIME
        .get()
        .ok_or_else(|| "互联核心尚未初始化。".to_owned())?;
    let mut receiver = runtime.subscribe();
    loop {
        match receiver.recv().await {
            Ok(event) => {
                if sink.add(event.to_string()).is_err() {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                if sink
                    .add(json!({"type":"state.resync","data":{}}).to_string())
                    .is_err()
                {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
    Ok(())
}
