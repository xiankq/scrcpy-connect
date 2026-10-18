//! Command boundary. Long-lived connections and activities belong to the Rust runtime.
use interop_core::Runtime;
use std::sync::{Arc, OnceLock};

pub(crate) mod event_observers;
use event_observers::{EventObservers, pump_events};

static RUNTIME: tokio::sync::OnceCell<Arc<Runtime>> = tokio::sync::OnceCell::const_new();
static EXECUTOR: OnceLock<tokio::runtime::Handle> = OnceLock::new();
static EVENT_OBSERVERS: OnceLock<EventObservers> = OnceLock::new();

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    log::set_max_level(log::LevelFilter::Info);
}

pub async fn initialize(data_directory: String) -> Result<(), String> {
    RUNTIME
        .get_or_try_init(|| async {
            let runtime = Runtime::initialize(data_directory)
                .await
                .map_err(|e| e.to_string())?;
            let _ = EXECUTOR.set(tokio::runtime::Handle::current());
            Ok::<_, String>(runtime)
        })
        .await?;
    Ok(())
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
    let mut command = None;
    let result = async {
        let request = crate::protocol::CommandRequest::decode(&request_json)?;
        command = Some(request.command);
        let runtime = RUNTIME.get().ok_or_else(|| {
            interop_core::CoreError::new("not_initialized", "互联核心尚未初始化。")
        })?;
        runtime
            .invoke(request.command.as_str(), request.params)
            .await
    }
    .await;
    crate::protocol::response(command, result)
}

/// Reserve one event observer before constructing Dart's async* listener.
/// Unused reservations expire after 60 seconds and count toward the 64-slot cap.
pub async fn open_events() -> Result<String, String> {
    RUNTIME
        .get()
        .ok_or_else(|| "互联核心尚未初始化。".to_owned())?;
    EVENT_OBSERVERS
        .get_or_init(EventObservers::bounded)
        .open()
        .map(|id| id.to_string())
}

/// Cancel only this observer; core connections and other observers keep running.
/// Dart must call this before awaiting StreamSubscription.cancel().
pub async fn cancel_events(subscription_id: String) -> Result<(), String> {
    let id =
        uuid::Uuid::parse_str(&subscription_id).map_err(|_| "事件订阅标识无效。".to_owned())?;
    EVENT_OBSERVERS
        .get_or_init(EventObservers::bounded)
        .cancel(id);
    Ok(())
}

pub async fn events(
    subscription_id: String,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    let id =
        uuid::Uuid::parse_str(&subscription_id).map_err(|_| "事件订阅标识无效。".to_owned())?;
    let Some(lease) = EVENT_OBSERVERS
        .get_or_init(EventObservers::bounded)
        .listen(id)?
    else {
        return Ok(());
    };
    let runtime = RUNTIME
        .get()
        .ok_or_else(|| "互联核心尚未初始化。".to_owned())?;
    pump_events(
        runtime.subscribe(),
        &lease.token,
        std::time::Duration::from_secs(15),
        |event| sink.add(event).is_ok(),
    )
    .await;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn concurrent_initialization_shares_one_identity_and_runtime() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().to_string_lossy().into_owned();
        let (first, second) =
            tokio::join!(super::initialize(root.clone()), super::initialize(root));
        first.unwrap();
        second.unwrap();
        let identity = tokio::fs::read(directory.path().join("host_identity.pem"))
            .await
            .unwrap();
        assert!(!identity.is_empty());
        super::initialize(directory.path().to_string_lossy().into_owned())
            .await
            .unwrap();
        assert_eq!(
            identity,
            tokio::fs::read(directory.path().join("host_identity.pem"))
                .await
                .unwrap()
        );
    }
}
