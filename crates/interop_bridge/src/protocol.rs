//! Validate the shared wire contract before entering the runtime.
//! Domain policy, ranges, permissions and resource ownership remain in core.
use crate::commands_generated::{Command, PROTOCOL_VERSION};
use interop_core::{CoreError, CoreResult};
use serde_json::{Value, json};

pub(crate) enum FieldType {
    String,
    Text,
    Integer,
    Number,
    Boolean,
    Object,
    Array,
}

pub(crate) struct Field {
    pub(crate) name: &'static str,
    pub(crate) kind: FieldType,
}

impl FieldType {
    fn accepts(&self, value: &Value) -> bool {
        match self {
            Self::String => value
                .as_str()
                .is_some_and(|s| !s.is_empty() && !s.contains('\0')),
            Self::Text => value.as_str().is_some_and(|s| !s.contains('\0')),
            Self::Integer => value.is_i64() || value.is_u64(),
            Self::Number => value.is_number(),
            Self::Boolean => value.is_boolean(),
            Self::Object => value.is_object(),
            Self::Array => value.is_array(),
        }
    }
}

pub(crate) struct CommandRequest {
    pub(crate) command: Command,
    pub(crate) params: Value,
}

impl CommandRequest {
    pub(crate) fn decode(raw: &str) -> CoreResult<Self> {
        if raw.len() > 1_048_576 {
            return Err(CoreError::new("request_limit", "操作内容过长。"));
        }
        let value: Value = serde_json::from_str(raw)?;
        if !value.is_object() {
            return Err(CoreError::new("invalid_argument", "操作请求必须是对象。"));
        }
        // Existing callers without an explicit version use the original v1.
        if let Some(version) = value.get("protocolVersion")
            && version.as_u64() != Some(PROTOCOL_VERSION)
        {
            return Err(CoreError::new(
                "protocol_version",
                "界面与互联核心版本不一致，请重新安装完整应用。",
            ));
        }
        let name = value["command"]
            .as_str()
            .ok_or_else(|| CoreError::new("invalid_argument", "缺少操作名称。"))?;
        let command = Command::parse(name)
            .ok_or_else(|| CoreError::new("unknown_command", format!("未知操作：{name}")))?;
        let params = value.get("params").cloned().unwrap_or_else(|| json!({}));
        validate_fields(
            &params,
            command.required(),
            command.optional(),
            "invalid_argument",
        )?;
        Ok(Self { command, params })
    }
}

fn validate_fields(
    value: &Value,
    required: &[Field],
    optional: &[Field],
    code: &str,
) -> CoreResult<()> {
    if !value.is_object() {
        return Err(CoreError::new(code, "操作内容必须是对象。"));
    }
    for field in required {
        if !field.kind.accepts(&value[field.name]) {
            return Err(CoreError::new(
                code,
                format!("缺少或无效的字段：{}", field.name),
            ));
        }
    }
    for field in optional {
        if let Some(v) = value.get(field.name).filter(|v| !v.is_null())
            && !field.kind.accepts(v)
        {
            return Err(CoreError::new(code, format!("无效的字段：{}", field.name)));
        }
    }
    Ok(())
}

pub(crate) fn response(command: Option<Command>, result: CoreResult<Value>) -> String {
    let result = result.and_then(|data| {
        validate_fields(
            &data,
            command.map(Command::result).unwrap_or(&[]),
            &[],
            "invalid_response",
        )?;
        Ok(data)
    });
    match result {
        Ok(data) => json!({"protocolVersion":PROTOCOL_VERSION,"ok":true,"data":data}),
        Err(error) => json!({"protocolVersion":PROTOCOL_VERSION,"ok":false,"error":{
            "code":error.code,"message":error.message,"details":error.details
        }}),
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reject_wrong_version_shape_and_unknown_commands_before_dispatch() {
        for (request, code) in [
            (json!([]), "invalid_argument"),
            (
                json!({"command":"devices.list","protocolVersion":2}),
                "protocol_version",
            ),
            (json!({"command":"devices.lsit"}), "unknown_command"),
            (
                json!({"command":"devices.list","params":[]}),
                "invalid_argument",
            ),
            (
                json!({"command":"devices.connect","params":{"deviceId":7}}),
                "invalid_argument",
            ),
            (
                json!({"command":"devices.connect","params":{"deviceId":""}}),
                "invalid_argument",
            ),
            (
                json!({"command":"documents.importFiles"}),
                "unknown_command",
            ),
        ] {
            assert_eq!(
                CommandRequest::decode(&request.to_string())
                    .err()
                    .unwrap()
                    .code,
                code
            );
        }
    }

    #[test]
    fn malformed_success_is_an_explicit_protocol_error() {
        let raw = response(Some(Command::DevicesList), Ok(json!({"device":[]})));
        let envelope: Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(envelope["protocolVersion"], PROTOCOL_VERSION);
        assert_eq!(envelope["ok"], false);
        assert_eq!(envelope["error"]["code"], "invalid_response");
        let raw = response(Some(Command::DevicesList), Ok(json!({"devices":[]})));
        assert_eq!(
            serde_json::from_str::<Value>(&raw).unwrap()["data"]["devices"],
            json!([])
        );
    }
}
