//! Opt-in test operator, never linked into the product. It changes only the
//! explicitly supplied isolated Android fixture through a second Rust runtime.
use interop_core::Runtime;
use serde_json::json;

#[tokio::main(worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::var("INTEROP_CLIPBOARD_FIXTURE").as_deref() != Ok("1") {
        return Err("Set INTEROP_CLIPBOARD_FIXTURE=1 for an isolated test target.".into());
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [endpoint, operation, rest @ ..] = args.as_slice() else {
        return Err("Usage: clipboard_fixture_client host:port get|set [fixture text]".into());
    };
    if !matches!(operation.as_str(), "get" | "set")
        || (operation == "get" && !rest.is_empty())
        || (operation == "set" && rest.len() != 1)
    {
        return Err("Expected get, or set with exactly one text argument.".into());
    }
    let (address, port) = endpoint.rsplit_once(':').ok_or("Expected host:port.")?;
    let address = address.trim_start_matches('[').trim_end_matches(']');
    let port = port.parse::<u16>()?;
    let private = tempfile::tempdir()?;
    let runtime = Runtime::initialize(private.path()).await?;
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":address,"port":port,"name":"Clipboard fixture"}),
        )
        .await?;
    let id = device["deviceId"].as_str().ok_or("Missing device ID.")?;
    let result = async {
        runtime
            .invoke("devices.connect", json!({"deviceId":id}))
            .await?;
        runtime
            .invoke(
                if operation == "get" {
                    "clipboard.get"
                } else {
                    "clipboard.set"
                },
                json!({"deviceId":id,"text":rest.first()}),
            )
            .await
    }
    .await;
    let disconnected = runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await;
    let result = result?;
    disconnected?;
    println!("{}", serde_json::to_string(&result)?);
    Ok(())
}
