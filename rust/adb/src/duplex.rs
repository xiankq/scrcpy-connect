//! 在已准入 ADB 服务上独立读写。任一半部释放只关闭该服务，不释放所属 Client。
use super::*;

pub struct AdbReader(pub(crate) AdbStream);
pub struct AdbWriter {
    inner: Arc<Inner>,
    local: u32,
    remote: u32,
    ack: mpsc::Receiver<u32>,
    server: Option<crate::server::Writer>,
    options: OperationOptions,
    closed: CancellationToken,
    poisoned: bool,
    priority: bool,
}
impl AdbStream {
    /// 写入等待对端 ACK/信用时继续读取。失败或取消的写入结果不明，此 writer 不能复用。
    pub fn into_split(mut self) -> (AdbReader, AdbWriter) {
        let (_, mut ack) = mpsc::channel(1);
        std::mem::swap(&mut ack, &mut self.ack);
        let writer = AdbWriter {
            inner: self.inner.clone(),
            local: self.local,
            remote: self.remote,
            ack,
            server: self.server.as_ref().map(crate::server::Stream::writer),
            options: self.options.clone(),
            closed: self.closed.clone(),
            poisoned: false,
            priority: self.priority_write,
        };
        (AdbReader(self), writer)
    }
}
impl AdbReader {
    pub async fn read(&mut self, output: &mut [u8]) -> Result<usize> {
        self.0.read(output).await
    }
    pub async fn close(self) -> Result<()> {
        self.0.close().await
    }
}
impl AdbWriter {
    pub async fn write_all(&mut self, bytes: &[u8]) -> Result<()> {
        if self.poisoned || self.closed.is_cancelled() {
            return Err(Error::Closed);
        }
        self.poisoned = true;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            tokio::select! {
                _ = self.inner.cancellation.cancelled() => Err(Error::Closed),
                _ = self.closed.cancelled() => Err(Error::Closed),
                result = async {
                    if let Some(server) = self.server.as_mut() {
                        server.write_all(bytes).await
                    } else {
                        write_stream_frames(&self.inner, self.local, self.remote,
                            &mut self.ack, bytes, self.priority).await
                    }
                } => result,
            }
        })
        .await;
        if result.is_ok() {
            self.poisoned = false;
        } else {
            self.close_now();
        }
        result
    }
    fn close_now(&mut self) {
        self.closed.cancel();
        if let Some(server) = &self.server {
            server.close();
        } else {
            let removed = self
                .inner
                .routes
                .lock()
                .expect("route mutex poisoned")
                .remove(&self.local);
            if removed.is_some() {
                self.inner
                    .queue_control(ControlResponse::OrderedClose(Frame::new(
                        protocol::CLSE,
                        self.local,
                        self.remote,
                        Vec::new(),
                    )));
            }
        }
    }
    pub fn close(mut self) {
        self.close_now();
    }
}
impl Drop for AdbWriter {
    fn drop(&mut self) {
        self.close_now();
    }
}
