//! Native media artifact execution. File and gallery business belongs to device_files.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{mime, remote_path, required},
};
use base64::Engine as _;
use interop_adb::{
    CancellationToken, OperationOptions,
    sync::{FileStat, RemotePath},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex as StdMutex, OnceLock, Weak},
    time::Duration,
};
use tokio::fs;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SourceStamp {
    pub(crate) size: u64,
    mode: u32,
    modified_seconds: i64,
    modified_nanos: u32,
}
impl From<FileStat> for SourceStamp {
    fn from(s: FileStat) -> Self {
        Self {
            size: s.size,
            mode: s.mode,
            modified_seconds: s.modified_seconds,
            modified_nanos: 0,
        }
    }
}
#[derive(Serialize, Deserialize)]
struct MediaCache {
    source: SourceStamp,
    local_size: u64,
    sha256: String,
}

const MAX_THUMBNAIL: usize = 256 * 1024;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ThumbnailSource {
    device: String,
    inode: String,
    mode: u32,
    size: u64,
    modified_seconds: i64,
    changed_seconds: i64,
    modified_nanos: Option<u32>,
    changed_nanos: Option<u32>,
}
impl ThumbnailSource {
    fn parse(value: &Value) -> CoreResult<Self> {
        let source: Self = serde_json::from_value(value.clone())?;
        if source.mode & 0o170000 != 0o100000
            || source.size > 64 * 1024 * 1024 * 1024
            || source.device.parse::<i64>().is_err()
            || source.inode.parse::<i64>().is_err()
            || source.modified_nanos.is_some_and(|n| n >= 1_000_000_000)
            || source.changed_nanos.is_some_and(|n| n >= 1_000_000_000)
        {
            return Err(CoreError::new("invalid_data", "缩略图源元数据无效。"));
        }
        Ok(source)
    }
    fn validation(&self) -> &'static str {
        if self.modified_nanos.is_some() && self.changed_nanos.is_some() {
            "descriptorDeviceInodeSizeModeMtimeCtimeWithNanosecondFields"
        } else {
            "descriptorDeviceInodeSizeModeMtimeCtimeSeconds"
        }
    }
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ThumbnailCache {
    version: u32,
    source: ThumbnailSource,
    sha256: String,
    jpeg_bytes: u64,
    width: u32,
    height: u32,
    #[serde(default)]
    artifact: String,
}
fn jpeg_dimensions(bytes: &[u8]) -> CoreResult<(u32, u32)> {
    let invalid = || CoreError::new("invalid_thumbnail", "缩略图 JPEG 结构或尺寸无效。");
    if !bytes.starts_with(&[0xff, 0xd8]) || !bytes.ends_with(&[0xff, 0xd9]) {
        return Err(invalid());
    }
    let mut offset = 2;
    while offset + 4 <= bytes.len() {
        if bytes[offset] != 0xff {
            return Err(invalid());
        }
        while offset < bytes.len() && bytes[offset] == 0xff {
            offset += 1;
        }
        let marker = *bytes.get(offset).ok_or_else(invalid)?;
        offset += 1;
        if marker == 0xda || marker == 0xd9 {
            return Err(invalid());
        }
        if marker == 0x01 || (0xd0..=0xd8).contains(&marker) {
            continue;
        }
        let length_bytes = bytes.get(offset..offset + 2).ok_or_else(invalid)?;
        let length = u16::from_be_bytes(length_bytes.try_into().expect("length")) as usize;
        if length < 2 || offset + length > bytes.len() {
            return Err(invalid());
        }
        if matches!(marker, 0xc0..=0xc2) {
            if length < 8 || bytes[offset + 2] != 8 {
                return Err(invalid());
            }
            let height =
                u16::from_be_bytes(bytes[offset + 3..offset + 5].try_into().expect("height"))
                    as u32;
            let width =
                u16::from_be_bytes(bytes[offset + 5..offset + 7].try_into().expect("width")) as u32;
            if width == 0 || height == 0 || width > 512 || height > 512 {
                return Err(invalid());
            }
            return Ok((width, height));
        }
        offset += length;
    }
    Err(invalid())
}

fn thumbnail_claim(key: &str, cancelled: bool) -> CoreResult<bool> {
    static SEEN: OnceLock<StdMutex<HashMap<String, bool>>> = OnceLock::new();
    let mut seen = SEEN
        .get_or_init(Default::default)
        .lock()
        .map_err(|_| CoreError::new("media_error", "缩略图操作标识不可用。"))?;
    if let Some(was_cancelled) = seen.get(key) {
        if cancelled {
            return Ok(false);
        }
        return Err(CoreError::new(
            if *was_cancelled {
                "cancelled"
            } else {
                "operation_reused"
            },
            "此缩略图操作已结束或取消，请使用新的操作标识。",
        ));
    }
    if seen.len() >= 65536 {
        return Err(CoreError::new(
            "operation_limit",
            "缩略图操作标识已达到本次进程上限，请重新打开应用。",
        ));
    }
    seen.insert(key.into(), cancelled);
    Ok(true)
}
fn thumbnail_identity(root: &Path, device: &str, operation: &str) -> (String, String) {
    let active = format!("thumbnail:{device}:{operation}");
    let seen = hex::encode(Sha256::digest(format!("{}:{active}", root.display())));
    (active, seen)
}
struct ThumbnailOperation {
    runtime: Weak<Runtime>,
    key: String,
    device: String,
    token: CancellationToken,
    phase: Arc<StdMutex<Option<String>>>,
    armed: bool,
}
impl Drop for ThumbnailOperation {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        self.token.cancel();
        let phase = self.phase.lock().ok().and_then(|mut phase| phase.take());
        let Some(runtime) = self.runtime.upgrade() else {
            return;
        };
        let key = self.key.clone();
        let device = self.device.clone();
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                if let Some(phase) = phase {
                    let _ = tokio::time::timeout(
                        Duration::from_secs(6),
                        runtime.cancel_companion_media(&device, &phase),
                    )
                    .await;
                }
                runtime.device_operations.lock().await.remove(&key);
            });
        }
    }
}
type CacheLocks = HashMap<String, Weak<tokio::sync::Mutex<()>>>;
fn cache_lock(key: &str) -> CoreResult<Arc<tokio::sync::Mutex<()>>> {
    static LOCKS: OnceLock<StdMutex<CacheLocks>> = OnceLock::new();
    let mut locks = LOCKS
        .get_or_init(Default::default)
        .lock()
        .map_err(|_| CoreError::new("cache_error", "媒体缓存锁不可用。"))?;
    locks.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = locks.get(key).and_then(Weak::upgrade) {
        return Ok(lock);
    }
    let lock = Arc::new(tokio::sync::Mutex::new(()));
    locks.insert(key.into(), Arc::downgrade(&lock));
    Ok(lock)
}
async fn file_digest(path: &Path) -> CoreResult<String> {
    use tokio::io::AsyncReadExt;
    let mut file = fs::File::open(path).await?;
    let mut buffer = vec![0u8; 64 * 1024];
    let mut hash = Sha256::new();
    loop {
        let n = file.read(&mut buffer).await?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
    }
    Ok(hex::encode(hash.finalize()))
}

impl Runtime {
    async fn thumbnail_rpc(
        self: &Arc<Self>,
        command: &str,
        mut params: Value,
        phase: &Arc<StdMutex<Option<String>>>,
    ) -> CoreResult<Value> {
        let operation = uuid::Uuid::new_v4().to_string();
        params["operationId"] = json!(operation);
        *phase
            .lock()
            .map_err(|_| CoreError::new("media_error", "缩略图操作状态不可用。"))? =
            Some(operation);
        let response = Box::pin(self.companion_command(command, &params)).await;
        *phase
            .lock()
            .map_err(|_| CoreError::new("media_error", "缩略图操作状态不可用。"))? = None;
        response
    }

    pub(crate) async fn cancel_thumbnail_media(self: &Arc<Self>, p: &Value) -> CoreResult<Value> {
        let device = required(p, "deviceId")?;
        self.device(device).await?;
        let operation = uuid::Uuid::parse_str(required(p, "operationId")?)
            .map_err(|_| CoreError::new("invalid_argument", "缩略图操作标识必须是 UUID。"))?
            .to_string();
        let (key, seen) = thumbnail_identity(&self.root, device, &operation);
        let active = self.device_operations.lock().await;
        let token = active.get(&key).cloned();
        let fresh = thumbnail_claim(&seen, true)?;
        if let Some(token) = &token {
            token.cancel();
        }
        drop(active);
        Ok(
            json!({"operationId":operation,"cancelRequested":token.is_some()||fresh,"alreadyFinished":token.is_none()&&!fresh,
            "status":if token.is_some(){"cancelling"}else if fresh{"cancelledBeforeStart"}else{"finished"}}),
        )
    }

    pub(crate) async fn thumbnail_media(self: &Arc<Self>, p: &Value) -> CoreResult<Value> {
        let device = required(p, "deviceId")?.to_owned();
        let path = remote_path(required(p, "path")?)?;
        let max_size = match p.get("maxSize") {
            None => 256,
            Some(value) => value
                .as_u64()
                .filter(|n| (64..=512).contains(n))
                .ok_or_else(|| {
                    CoreError::new("invalid_argument", "缩略图尺寸必须在 64–512 之间。")
                })? as u32,
        };
        let kind = if mime(&path).starts_with("image/") {
            "image"
        } else if mime(&path).starts_with("video/") {
            "video"
        } else {
            return Err(CoreError::new(
                "media_type_unknown",
                "此路径的媒体类型尚未识别，不能自动下载原内容作为缩略图。",
            ));
        };
        let operation = match p.get("operationId") {
            None => uuid::Uuid::new_v4(),
            Some(Value::String(value)) => uuid::Uuid::parse_str(value)
                .map_err(|_| CoreError::new("invalid_argument", "缩略图操作标识必须是 UUID。"))?,
            _ => return Err(CoreError::new("invalid_argument", "缩略图操作标识无效。")),
        }
        .to_string();
        let (key, seen) = thumbnail_identity(&self.root, &device, &operation);
        let token = CancellationToken::new();
        {
            let mut active = self.device_operations.lock().await;
            let prefix = format!("thumbnail:{device}:");
            if active.keys().filter(|key| key.starts_with(&prefix)).count() >= 16 {
                return Err(CoreError::new(
                    "busy",
                    "这台设备正在处理的缩略图请求已达到上限。",
                ));
            }
            // Publish ownership and the cancellation token under the same lock
            // used by cancel, including cancellation arriving before start.
            thumbnail_claim(&seen, false)?;
            active.insert(key.clone(), token.clone());
        }
        let phase = Arc::new(StdMutex::new(None));
        let mut guard = ThumbnailOperation {
            runtime: Arc::downgrade(self),
            key: key.clone(),
            device: device.clone(),
            token: token.clone(),
            phase: phase.clone(),
            armed: true,
        };
        self.emit(
            "media.thumbnail.started",
            Some(&device),
            json!({"operationId":operation}),
        );
        let job = Box::pin(async {
            self.client(&device).await?;
            Box::pin(self.thumbnail_cached(&device, &path, kind, max_size, &operation, &phase))
                .await
        });
        let result = tokio::select! {
            biased;
            _=token.cancelled()=>Err(CoreError::new("cancelled","缩略图请求已取消；不会返回原件或继续发布结果。")),
            result=tokio::time::timeout(Duration::from_secs(45), job)=>result.unwrap_or_else(|_|Err(CoreError::new("media_timeout","缩略图请求超过有界等待时间。"))),
        };
        if result.is_err() {
            let current = phase.lock().ok().and_then(|mut phase| phase.take());
            if let Some(current) = current {
                let cleanup = tokio::time::timeout(
                    Duration::from_secs(6),
                    self.cancel_companion_media(&device, &current),
                )
                .await;
                if !cleanup
                    .as_ref()
                    .is_ok_and(|result| result.as_ref().is_ok_and(|value| value["reaped"] == true))
                {
                    guard.armed = false;
                    self.device_operations.lock().await.remove(&key);
                    return Err(CoreError::new(
                        "media_cleanup_unknown",
                        "解码子进程尚未确认回收；没有发布缩略图。",
                    ));
                }
            }
        }
        guard.armed = false;
        self.device_operations.lock().await.remove(&key);
        let mut result = result?;
        if token.is_cancelled() {
            if let Some(lease) = result["cacheLeaseId"].as_str() {
                let _ = self
                    .cache_command("media.cache.release", &json!({"leaseId":lease}))
                    .await;
            }
            return Err(CoreError::new(
                "cancelled",
                "缩略图请求已取消，没有发布结果。",
            ));
        }
        result["operationId"] = json!(operation);
        Ok(result)
    }

    async fn thumbnail_cached(
        self: &Arc<Self>,
        device: &str,
        path: &str,
        kind: &str,
        max_size: u32,
        operation: &str,
        phase: &Arc<StdMutex<Option<String>>>,
    ) -> CoreResult<Value> {
        // Serial per-device decode keeps media memory/CPU bounded independently
        // of the notification/clipboard worker. Active request count is capped.
        let gate = cache_lock(&format!(
            "{}:thumbnail-device:{device}",
            self.root.display()
        ))?;
        let _guard = gate.lock().await;
        let key = hex::encode(Sha256::digest(format!(
            "thumbnail-v1\0{device}\0{path}\0{max_size}"
        )));
        let params = json!({"deviceId":device,"path":path,"kind":kind,"maxSize":max_size,"ownerOperationId":operation});
        let before = Box::pin(self.thumbnail_rpc("media.stat", params.clone(), phase)).await?;
        let source = ThumbnailSource::parse(&before["sourceStamp"])?;
        let version = hex::encode(Sha256::digest(serde_json::to_vec(&source)?));
        let cache = self
            .root
            .join("media")
            .join("thumbnails")
            .join(format!("{key}-{version}"));
        let lookup = self.cache_writer(cache.clone(), 0).await?;
        fs::create_dir_all(&cache).await?;
        let metadata_path = cache.join("metadata.json");
        let mut transferred = before["rpcBytesReceived"].as_u64().unwrap_or(0);
        let cached = if fs::metadata(&metadata_path)
            .await
            .is_ok_and(|metadata| metadata.len() <= 4096)
        {
            fs::read(&metadata_path)
                .await
                .ok()
                .and_then(|bytes| serde_json::from_slice::<ThumbnailCache>(&bytes).ok())
        } else {
            None
        };
        if let Some(cached) = &cached
            && cached.version == 1
            && cached.source == source
            && cached.jpeg_bytes <= MAX_THUMBNAIL as u64
            && cached.sha256.len() == 64
            && cached.sha256.bytes().all(|byte| byte.is_ascii_hexdigit())
            && !cached.artifact.is_empty()
            && !cached.artifact.contains('/')
            && !cached.artifact.contains('\\')
            && !cached.artifact.contains("..")
        {
            let target = cache.join(&cached.artifact);
            if fs::symlink_metadata(&target)
                .await
                .is_ok_and(|meta| meta.is_file() && meta.len() == cached.jpeg_bytes)
                && let Ok(bytes) = fs::read(&target).await
                && hex::encode(Sha256::digest(&bytes)) == cached.sha256
                && jpeg_dimensions(&bytes).is_ok_and(|dimensions| {
                    dimensions == (cached.width, cached.height)
                        && dimensions.0 <= max_size
                        && dimensions.1 <= max_size
                })
            {
                let _gate = self.media_cache.gate.lock().await;
                let lease = self.media_cache.lease(vec![cache.clone()]);
                return Ok(
                    json!({"localPath":target,"cacheLeaseId":lease,"mime":"image/jpeg","thumbnail":true,"width":cached.width,"height":cached.height,
                "originalSize":source.size,"cacheHit":true,"sourceStamp":source,"sourceValidation":source.validation(),
                "bytesTransferred":transferred,"jpegBytes":cached.jpeg_bytes,"jpegBytesTransferred":0,"originalBytesTransferred":0,"transferAccounting":"companionJsonPayloadBytes"}),
                );
            }
        }
        drop(lookup);
        let writer = self
            .cache_writer(cache.clone(), MAX_THUMBNAIL as u64 + 4096)
            .await?;
        let response =
            Box::pin(self.thumbnail_rpc("media.thumbnail", params.clone(), phase)).await?;
        transferred =
            transferred.saturating_add(response["rpcBytesReceived"].as_u64().unwrap_or(0));
        if ThumbnailSource::parse(&response["sourceStamp"])? != source
            || response["thumbnail"] != true
            || response["mime"] != "image/jpeg"
        {
            return Err(CoreError::new(
                "source_changed",
                "生成期间媒体源或返回的缩略图类型发生变化。",
            ));
        }
        let encoded = response["data"]
            .as_str()
            .filter(|text| text.len() <= MAX_THUMBNAIL.div_ceil(3) * 4)
            .ok_or_else(|| CoreError::new("invalid_thumbnail", "缩略图数据缺失或超过大小限制。"))?;
        let jpeg = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .map_err(|_| CoreError::new("invalid_thumbnail", "缩略图编码无效。"))?;
        let sha256 = hex::encode(Sha256::digest(&jpeg));
        let (width, height) = jpeg_dimensions(&jpeg)?;
        if jpeg.len() > MAX_THUMBNAIL
            || response["sha256"] != sha256
            || response["jpegBytes"] != jpeg.len() as u64
            || response["width"] != width
            || response["height"] != height
            || width > max_size
            || height > max_size
        {
            return Err(CoreError::new(
                "invalid_thumbnail",
                "缩略图摘要、大小或尺寸不一致。",
            ));
        }
        let after = Box::pin(self.thumbnail_rpc("media.stat", params, phase)).await?;
        transferred = transferred.saturating_add(after["rpcBytesReceived"].as_u64().unwrap_or(0));
        if ThumbnailSource::parse(&after["sourceStamp"])? != source {
            return Err(CoreError::new(
                "source_changed",
                "媒体源已经变化，请重新获取缩略图。",
            ));
        }
        let artifact = format!("{}-{sha256}.jpg", uuid::Uuid::new_v4());
        let target = cache.join(&artifact);
        let metadata = ThumbnailCache {
            version: 1,
            source: source.clone(),
            sha256,
            jpeg_bytes: jpeg.len() as u64,
            width,
            height,
            artifact,
        };
        Self::private_write(&target, &jpeg).await?;
        Self::private_write(&metadata_path, &serde_json::to_vec(&metadata)?).await?;
        let _gate = self.media_cache.gate.lock().await;
        let lease = self.media_cache.lease(vec![cache]);
        drop(writer);
        Ok(
            json!({"localPath":target,"cacheLeaseId":lease,"mime":"image/jpeg","thumbnail":true,"width":width,"height":height,"originalSize":source.size,
            "cacheHit":false,"sourceStamp":source,"sourceValidation":source.validation(),"bytesTransferred":transferred,
            "jpegBytes":jpeg.len(),"jpegBytesTransferred":jpeg.len(),"originalBytesTransferred":0,"transferAccounting":"companionJsonPayloadBytes",
            "orientationApplied":response["orientationApplied"],"orientation":response["orientation"],"videoRotation":response["videoRotation"]}),
        )
    }

    pub(crate) async fn preview_media(&self, p: &Value) -> CoreResult<Value> {
        let path = remote_path(required(p, "path")?)?;
        let id = required(p, "deviceId")?;
        let client = self.client(id).await?;
        let key = hex::encode(Sha256::digest(format!("{id}\0{path}")));
        let lock = cache_lock(&format!("{}:{key}", self.root.display()))?;
        let _guard = lock.lock().await;
        let cache = self.root.join("media");
        fs::create_dir_all(&cache).await?;
        let extension = Path::new(&path)
            .extension()
            .and_then(|v| v.to_str())
            .filter(|v| v.len() <= 12 && v.bytes().all(|b| b.is_ascii_alphanumeric()))
            .unwrap_or("bin");
        let options = OperationOptions {
            timeout: Duration::from_secs(300),
            ..Default::default()
        };
        let source = SourceStamp::from(
            crate::remote_fs::stat(&client, &path, false, options.clone()).await?,
        );
        if source.mode & 0o170000 != 0o100000 {
            return Err(CoreError::new("not_a_file", "预览源必须是普通文件。"));
        }
        // Version the artifact by the observed source stamp, and use a fresh
        // filename on repair. An existing player's file is never replaced.
        let version = hex::encode(Sha256::digest(serde_json::to_vec(&source)?));
        let cache = cache.join(format!("{key}-{version}"));
        let lookup = self.cache_writer(cache.clone(), 0).await?;
        fs::create_dir_all(&cache).await?;
        let metadata_path = cache.join("metadata.json");
        let cached = fs::read(&metadata_path)
            .await
            .ok()
            .and_then(|b| serde_json::from_slice::<MediaCache>(&b).ok());
        let target = fs::read_to_string(cache.join("current"))
            .await
            .ok()
            .filter(|name| !name.contains('/') && !name.contains('\\') && !name.contains(".."))
            .map(|name| cache.join(name));
        if let Some(cached) = cached
            && let Some(target) = target
            && cached.source == source
            && fs::metadata(&target)
                .await
                .is_ok_and(|m| m.is_file() && m.len() == cached.local_size)
            && file_digest(&target).await? == cached.sha256
        {
            let _gate = self.media_cache.gate.lock().await;
            let lease = self.media_cache.lease(vec![cache.clone()]);
            return Ok(
                json!({"localPath":target,"cacheLeaseId":lease,"mime":mime(&path),"cacheHit":true,"size":source.size,"sourceValidation":"sizeModeMtimeSeconds","thumbnail":false}),
            );
        }
        drop(lookup);
        let writer = self
            .cache_writer(cache.clone(), source.size.saturating_add(4096))
            .await?;
        let target = cache.join(format!("{}.{}", uuid::Uuid::new_v4(), extension));
        let temp = cache.join(format!(".{key}-{}.part", uuid::Uuid::new_v4()));
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .await?;
        let result: CoreResult<MediaCache> = async {
            let mut sync = client.sync(options.clone()).await?;
            let count = sync
                .pull(&RemotePath::new(&path)?, &mut file, source.size)
                .await?;
            file.sync_all().await?;
            drop(sync);
            let after =
                SourceStamp::from(crate::remote_fs::stat(&client, &path, false, options).await?);
            if count != source.size || after != source {
                return Err(CoreError::new(
                    "source_changed",
                    "预览源文件发生变化，请重新打开。",
                ));
            }
            Ok(MediaCache {
                source,
                local_size: count,
                sha256: file_digest(&temp).await?,
            })
        }
        .await;
        drop(file);
        let metadata = match result {
            Ok(meta) => meta,
            Err(error) => {
                let _ = fs::remove_file(&temp).await;
                return Err(error);
            }
        };
        fs::rename(&temp, &target).await?;
        Self::private_write(&metadata_path, &serde_json::to_vec(&metadata)?).await?;
        Self::private_write(
            &cache.join("current"),
            target.file_name().unwrap().to_string_lossy().as_bytes(),
        )
        .await?;
        let _gate = self.media_cache.gate.lock().await;
        let lease = self.media_cache.lease(vec![cache]);
        drop(writer);
        Ok(
            json!({"localPath":target,"cacheLeaseId":lease,"mime":mime(&path),"cacheHit":false,"size":metadata.source.size,"sourceValidation":"sizeModeMtimeSeconds","thumbnail":false}),
        )
    }
}

#[cfg(test)]
mod thumbnail_tests {
    use super::*;
    #[test]
    fn thumbnail_metadata_checks_stamp_fields_and_bounded_jpeg_dimensions() {
        let stamp = json!({"device":"1","inode":"2","mode":0o100600,"size":512,
            "modifiedSeconds":1,"changedSeconds":2,"modifiedNanos":null,"changedNanos":null});
        let source = ThumbnailSource::parse(&stamp).unwrap();
        assert!(source.validation().ends_with("Seconds"));
        let mut nanos = stamp.clone();
        nanos["modifiedNanos"] = json!(999_999_999);
        nanos["changedNanos"] = json!(0);
        assert!(
            ThumbnailSource::parse(&nanos)
                .unwrap()
                .validation()
                .ends_with("WithNanosecondFields")
        );
        nanos["modifiedNanos"] = json!(1_000_000_000);
        assert!(ThumbnailSource::parse(&nanos).is_err());
        let mut link = stamp;
        link["mode"] = json!(0o120777);
        assert!(ThumbnailSource::parse(&link).is_err());
        let jpeg = [255, 216, 255, 192, 0, 8, 8, 0, 64, 0, 128, 1, 255, 217];
        assert_eq!(jpeg_dimensions(&jpeg).unwrap(), (128, 64));
        for i in 0..jpeg.len() {
            assert!(jpeg_dimensions(&jpeg[..i]).is_err());
        }
        let mut oversized = jpeg;
        oversized[9] = 3;
        assert!(jpeg_dimensions(&oversized).is_err());
        let mut segment = jpeg;
        segment[5] = 255;
        assert!(jpeg_dimensions(&segment).is_err());
    }
}
