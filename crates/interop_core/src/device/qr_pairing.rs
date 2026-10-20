use super::*;

impl Runtime {
    pub(crate) async fn qr_pairing(self: &Arc<Self>, params: &Value) -> CoreResult<Value> {
        let device = params["deviceId"].as_str().map(str::to_owned);
        if let Some(id) = &device {
            self.device(id).await?;
        }
        let material = self.identities.selected(device.as_deref()).await?;
        let op = self
            .new_setup_operation(params, device.as_deref(), material.fingerprint.clone())
            .await?;
        let qr = QrPairing::generate();
        let response = json!({"payload":qr.payload().as_str(),"serviceName":qr.service_name(),"attemptId":op.attempt_id,"operationId":op.id,"expiresAt":now()+self.connection_policy.qr_pairing_timeout_ms.div_ceil(1000)});
        let runtime = self.clone();
        tokio::spawn(async move {
            let options = OperationOptions {
                timeout: Duration::from_millis(runtime.connection_policy.qr_pairing_timeout_ms),
                cancellation: op.token.clone(),
            };
            let result = tokio::select! {
                _ = op.token.cancelled() => Err(CoreError::new("cancelled","配对执行已取消。")),
                result = tokio::time::timeout(options.timeout, async {
                    let discovery = Discovery::new()?;
                    let tls = material.tls().await?;
                    loop {
                        if let DiscoveryEvent::Resolved(service) = discovery.next(&options).await?
                            && service.kind == ServiceKind::Pairing && service.instance == qr.service_name() {
                            let mut last = None;
                            let endpoint_options = OperationOptions {
                                timeout: Duration::from_millis(runtime.connection_policy.endpoint_timeout_ms),
                                cancellation: op.token.clone(),
                            };
                            for address in service.endpoints {
                                // Bound TCP and the entire PAKE exchange together. A
                                // silent interface must leave time for other addresses.
                                let paired = tokio::time::timeout(endpoint_options.timeout, async {
                                    let socket = tokio::net::TcpStream::connect(address).await?;
                                    Ok::<_, CoreError>(wireless::pair(socket,qr.password(),&material.identity,&tls,&runtime.connection_policy.public_key_comment,&endpoint_options).await?)
                                }).await.unwrap_or_else(|_|Err(CoreError::new("timeout","配对地址响应超时。")));
                                match paired {
                                    Ok(paired) => return runtime.finish_pairing_record(paired.guid,address_of(address),device.as_deref(),&op).await,
                                    Err(error) => { if authorization_failed(&error) { return Err(error); } last = Some(error); }
                                }
                            }
                            return Err(last.unwrap_or_else(||CoreError::new("unreachable","配对服务没有可达地址。")));
                        }
                    }
                }) => result.unwrap_or_else(|_|Err(CoreError::new("expired","配对执行已过期。"))),
            };
            runtime.setup_outcome(&op, &result);
        });
        Ok(response)
    }
}
