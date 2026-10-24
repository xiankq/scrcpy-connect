//! 轮换操作句柄，原 Client、捕获 lifetime 与连接登记身份始终保持。
use super::*;

pub(super) async fn claim(id: &str, timeout: Duration) -> Result<AdbDeviceInfo, String> {
    claim_registered(id, timeout, None).await
}

pub(super) async fn claim_registered(
    id: &str,
    timeout: Duration,
    handshake: Option<&str>,
) -> Result<AdbDeviceInfo, String> {
    let gate = {
        let state = registry().lock().expect("adb registry");
        if let Some(handshake) = handshake {
            handshake::validate_registration(&state, handshake)?;
        }
        if handshake::has_unconfirmed_connection(&state, id) {
            return Err("adb_connection_not_delivered".into());
        }
        let connection = state.connections.get(id).ok_or("adb_connection_closed")?;
        if !connection.owned {
            return Err("adb_connection_borrowed".into());
        }
        connection.transition.clone()
    };
    tokio::time::timeout(timeout, async {
        let _transition = gate.lock().await;
        let (client, owner, operations) = {
            let mut state = registry().lock().expect("adb registry");
            if state.closing {
                return Err("adb_host_closing".into());
            }
            if let Some(handshake) = handshake {
                handshake::validate_registration(&state, handshake)?;
            }
            let connection = state
                .connections
                .get_mut(id)
                .ok_or("adb_connection_closed")?;
            if !connection.owned {
                return Err("adb_connection_borrowed".into());
            }
            if connection.scope.is_cancelled() || connection.client.is_closed() {
                return Err("adb_connection_closed".into());
            }
            connection.accepting = false;
            connection.service_scope.cancel();
            let client = connection.client.clone();
            let owner = connection.owner.clone();
            let operations = state
                .operations
                .iter()
                .filter(|(_, op)| op.connection == id)
                .map(|(id, op)| {
                    op.stop.cancel();
                    id.clone()
                })
                .collect::<Vec<_>>();
            (client, owner, operations)
        };
        // 已撤销旧准入；各项失败仍继续回收其余资源，未确认项保持原句柄重试。
        let mut failure = crate::file_system::cancel_connection(id).await.err();
        for operation in operations {
            if let Err(error) = cancel_with_timeout(&operation, timeout).await {
                failure.get_or_insert(error);
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        flush_client(&client, timeout).await?;
        let mut state = registry().lock().expect("adb registry");
        if state.closing {
            return Err("adb_host_closing".into());
        }
        if let Some(handshake) = handshake {
            handshake::validate_registration(&state, handshake)?;
        }
        let connection = state.connections.get(id).ok_or("adb_connection_closed")?;
        if connection.owner != owner
            || connection.scope.is_cancelled()
            || connection.client.is_closed()
        {
            return Err("adb_connection_closed".into());
        }
        let next = uuid::Uuid::new_v4().to_string();
        let mut connection = state.connections.remove(id).expect("转换锁保持原登记");
        connection.service_scope = connection.scope.child_token();
        connection.accepting = true;
        let info = AdbDeviceInfo {
            id: next.clone(),
            serial: connection.serial.clone(),
            state: "device".into(),
            features: connection.client.info().features.iter().cloned().collect(),
        };
        state.connections.insert(next, connection);
        if let Some(handshake) = handshake {
            handshake::retain_connection(&mut state, handshake, &info.id);
        }
        Ok(info)
    })
    .await
    .map_err(|_| "adb_connection_claim_unconfirmed".to_owned())?
}
