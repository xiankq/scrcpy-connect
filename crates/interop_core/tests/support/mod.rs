/// Concrete parameters chosen by this test host, rather than Runtime defaults.
pub fn media_params(patch: serde_json::Value) -> serde_json::Value {
    let mut result = serde_json::json!({
        "maxSize":1280,"maxFps":60,"videoBitRate":8_000_000,
        "videoCodec":"h264","videoEncoder":null,
    });
    for (key, value) in patch.as_object().expect("fixture parameters") {
        result[key] = value.clone();
    }
    result
}
