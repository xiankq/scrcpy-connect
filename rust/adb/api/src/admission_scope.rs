//! 调用方命名的握手准入与交接。旧权限先撤销，实际工作排空后才交付后继权限。
use super::*;

pub(super) struct Scope {
    pub(super) id: String,
    pub(super) accepting: bool,
}

fn key(value: &str) -> Result<(), String> {
    if value.is_empty() || value.len() > 1024 || value.chars().any(char::is_control) {
        return Err("invalid_adb_admission_scope".into());
    }
    Ok(())
}

fn facts(name: &str, scope: &Scope) -> AdbAdmissionScopeInfo {
    AdbAdmissionScopeInfo {
        scope_key: name.into(),
        scope_id: scope.id.clone(),
        accepting: scope.accepting,
    }
}

pub(super) fn inspect(name: &str) -> Result<Option<AdbAdmissionScopeInfo>, String> {
    key(name)?;
    let state = registry().lock().expect("adb registry");
    Ok(state
        .admission_scopes
        .get(name)
        .map(|scope| facts(name, scope)))
}

pub(super) fn validate(state: &MobileAdbRegistry, id: &str) -> Result<(), String> {
    if state.closing {
        return Err("adb_host_closing".into());
    }
    if state
        .admission_scopes
        .values()
        .any(|scope| scope.id == id && scope.accepting)
    {
        Ok(())
    } else {
        Err("adb_admission_scope_stale".into())
    }
}

fn gate(name: &str) -> Result<Arc<AsyncMutex<()>>, String> {
    let mut state = registry().lock().expect("adb registry");
    let MobileAdbRegistry {
        admission_scopes,
        admission_gates,
        ..
    } = &mut *state;
    admission_gates
        .retain(|key, gate| Arc::strong_count(gate) > 1 || admission_scopes.contains_key(key));
    if !admission_gates.contains_key(name) && admission_gates.len() >= 128 {
        return Err("adb_admission_scope_limit".into());
    }
    Ok(admission_gates.entry(name.into()).or_default().clone())
}

/// 文件域附着与父域交接共享同一转换锁；旧调用不能按相同文件名称夺取后继权限。
pub(super) async fn attach_file_scope(
    owner_key: String,
    scope_id: String,
) -> Result<String, String> {
    let name = {
        let state = registry().lock().expect("adb registry");
        validate(&state, &scope_id)?;
        state
            .admission_scopes
            .iter()
            .find(|(_, scope)| scope.id == scope_id)
            .map(|(name, _)| name.clone())
            .ok_or("adb_admission_scope_stale")?
    };
    let gate = gate(&name)?;
    let _transition = gate.lock().await;
    {
        let state = registry().lock().expect("adb registry");
        validate(&state, &scope_id)?;
    }
    let id = crate::file_system::attach_scope_with_admission(owner_key, scope_id.clone()).await?;
    let validation = validate(&registry().lock().expect("adb registry"), &scope_id);
    if let Err(error) = validation {
        // close_all 不持单域转换锁；其间撤准入时不能把晚到文件域交给调用方。
        // 精确登记仍保留在父域下，关闭失败可由原 scope 重试回收。
        crate::file_system::close_scope(&id).await?;
        return Err(error);
    }
    Ok(id)
}

pub(super) async fn attach(
    name: String,
    expected: Option<String>,
    timeout: Duration,
) -> Result<AdbAdmissionScopeInfo, String> {
    key(&name)?;
    let gate = gate(&name)?;
    tokio::time::timeout(timeout, async {
        let _transition = gate.lock().await;
        {
            let state = registry().lock().expect("adb registry");
            if state.closing {
                return Err("adb_host_closing".into());
            }
            if state.admission_scopes.get(&name).map(|scope| &scope.id) != expected.as_ref() {
                return Err("adb_admission_scope_stale".into());
            }
        }
        if let Some(id) = &expected {
            drain(id, timeout).await?;
        }
        let mut state = registry().lock().expect("adb registry");
        if state.closing {
            return Err("adb_host_closing".into());
        }
        if state.admission_scopes.get(&name).map(|scope| &scope.id) != expected.as_ref() {
            return Err("adb_admission_scope_stale".into());
        }
        let scope = Scope {
            id: uuid::Uuid::new_v4().to_string(),
            accepting: true,
        };
        let result = facts(&name, &scope);
        state.admission_scopes.insert(name, scope);
        Ok(result)
    })
    .await
    .map_err(|_| "adb_admission_scope_cleanup_unconfirmed".to_owned())?
}

async fn drain(id: &str, timeout: Duration) -> Result<(), String> {
    let (handshakes, servers, files) = {
        let mut state = registry().lock().expect("adb registry");
        if let Some(scope) = state
            .admission_scopes
            .values_mut()
            .find(|scope| scope.id == id)
        {
            scope.accepting = false;
        }
        (
            handshake::revoke_scope(&state, id),
            server_owner::revoke_scope(&mut state, id),
            crate::file_system::revoke_admission(id),
        )
    };
    let mut failure = None;
    for handshake in handshakes {
        if let Err(error) = handshake::close(&handshake, timeout).await {
            failure.get_or_insert(error);
        }
    }
    // 文件关闭依赖仍存活的 Client；关闭帧和精确暂存描述符完成后，才回收未交付服务器。
    if let Err(error) = crate::file_system::drain_admission(files).await {
        failure.get_or_insert(error);
    } else if let Err(error) = server_owner::drain_scope(servers, timeout).await {
        failure.get_or_insert(error.to_string());
    }
    failure.map_or(Ok(()), |_| {
        Err("adb_admission_scope_cleanup_unconfirmed".into())
    })
}

pub(super) async fn close(id: &str, timeout: Duration) -> Result<(), String> {
    let name = {
        let state = registry().lock().expect("adb registry");
        state
            .admission_scopes
            .iter()
            .find(|(_, scope)| scope.id == id)
            .map(|(name, _)| name.clone())
    };
    let Some(name) = name else {
        return Ok(());
    };
    let gate = gate(&name)?;
    tokio::time::timeout(timeout, async {
        let _transition = gate.lock().await;
        if registry()
            .lock()
            .expect("adb registry")
            .admission_scopes
            .get(&name)
            .is_none_or(|scope| scope.id != id)
        {
            return Ok(());
        }
        drain(id, timeout).await?;
        registry()
            .lock()
            .expect("adb registry")
            .admission_scopes
            .remove(&name);
        Ok(())
    })
    .await
    .map_err(|_| "adb_admission_scope_cleanup_unconfirmed".to_owned())?
}
