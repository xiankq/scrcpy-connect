//! One verified, immutable copy of each temporary Android execution artifact.
//! Android receives these bytes from Flutter's shared compressed assets. Other
//! hosts retain a compressed fallback so the Rust core also runs on its own.
use crate::{CoreError, CoreResult};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{path::Path, sync::OnceLock};

const MANIFEST: &str =
    include_str!("../../../packages/interop_bridge/assets/servers/manifest.json");
const IDS: [&str; 6] = [
    "scrcpy",
    "companion",
    "arm64-v8a",
    "armeabi-v7a",
    "x86_64",
    "x86",
];
static ARTIFACTS: OnceLock<Artifacts> = OnceLock::new();

#[derive(Deserialize)]
struct Manifest {
    version: u32,
    artifacts: Vec<Artifact>,
}

#[derive(Deserialize)]
struct Artifact {
    id: String,
    file: String,
    sha256: String,
    size: usize,
}

struct Artifacts(Vec<(String, Box<[u8]>)>);

fn integrity(id: &str, detail: impl std::fmt::Display) -> CoreError {
    let code = if IDS[2..].contains(&id) {
        "helper_integrity"
    } else {
        "server_integrity"
    };
    CoreError::new(code, format!("内置执行产物 {id} 校验失败：{detail}"))
}

fn manifest() -> CoreResult<Manifest> {
    let manifest: Manifest =
        serde_json::from_str(MANIFEST).map_err(|error| integrity("manifest", error))?;
    if manifest.version != 1 || manifest.artifacts.len() != IDS.len() {
        return Err(integrity("manifest", "清单版本或产物数量无效。"));
    }
    for id in IDS {
        let mut matching = manifest.artifacts.iter().filter(|entry| entry.id == id);
        let entry = matching
            .next()
            .ok_or_else(|| integrity(id, "清单缺少产物。"))?;
        if matching.next().is_some()
            || entry.file != format!("{id}.zlib")
            || entry.size == 0
            || entry.size == usize::MAX
            || entry.sha256.len() != 64
            || !entry.sha256.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(integrity(id, "清单产物信息无效。"));
        }
    }
    Ok(manifest)
}

fn verify(entry: &Artifact, bytes: &[u8]) -> CoreResult<()> {
    if bytes.len() != entry.size {
        return Err(integrity(&entry.id, "长度不符。"));
    }
    if hex::encode(Sha256::digest(bytes)) != entry.sha256 {
        return Err(integrity(&entry.id, "SHA-256 不符。"));
    }
    Ok(())
}

#[cfg(not(target_os = "android"))]
fn decode(entry: &Artifact, compressed: &[u8]) -> CoreResult<Box<[u8]>> {
    use flate2::{Decompress, FlushDecompress, Status};
    // One extra byte distinguishes oversized data without unbounded allocation.
    let mut bytes = Vec::with_capacity(entry.size + 1);
    let mut decoder = Decompress::new(true);
    let status = decoder
        .decompress_vec(compressed, &mut bytes, FlushDecompress::Finish)
        .map_err(|error| integrity(&entry.id, error))?;
    if status != Status::StreamEnd || decoder.total_in() != compressed.len() as u64 {
        return Err(integrity(&entry.id, "压缩流损坏、未结束或存在多余数据。"));
    }
    verify(entry, &bytes)?;
    Ok(bytes.into_boxed_slice())
}

#[cfg(not(target_os = "android"))]
fn embedded(id: &str) -> &'static [u8] {
    match id {
        "scrcpy" => include_bytes!("../../../packages/interop_bridge/assets/servers/scrcpy.zlib"),
        "companion" => {
            include_bytes!("../../../packages/interop_bridge/assets/servers/companion.zlib")
        }
        "arm64-v8a" => {
            include_bytes!("../../../packages/interop_bridge/assets/servers/arm64-v8a.zlib")
        }
        "armeabi-v7a" => {
            include_bytes!("../../../packages/interop_bridge/assets/servers/armeabi-v7a.zlib")
        }
        "x86_64" => include_bytes!("../../../packages/interop_bridge/assets/servers/x86_64.zlib"),
        "x86" => include_bytes!("../../../packages/interop_bridge/assets/servers/x86.zlib"),
        _ => unreachable!("only manifest-validated IDs reach the embedded source"),
    }
}

#[cfg(any(target_os = "android", test))]
fn from_directory(directory: &Path) -> CoreResult<Artifacts> {
    let mut artifacts = Vec::with_capacity(IDS.len());
    for entry in manifest()?.artifacts {
        let path = directory.join(&entry.id);
        // Bound reads even when a file was replaced with an oversized payload.
        use std::io::Read;
        let mut bytes = Vec::with_capacity(entry.size + 1);
        std::fs::File::open(&path)
            .and_then(|file| file.take((entry.size + 1) as u64).read_to_end(&mut bytes))
            .map_err(|error| integrity(&entry.id, error))?;
        verify(&entry, &bytes)?;
        artifacts.push((entry.id, bytes.into_boxed_slice()));
    }
    Ok(Artifacts(artifacts))
}

fn prepare_with(
    cache: &OnceLock<Artifacts>,
    load: impl FnOnce() -> CoreResult<Artifacts>,
) -> CoreResult<()> {
    if cache.get().is_none() {
        // Build the complete candidate first. A failure cannot poison the cache;
        // concurrent successful initialization can safely discard a duplicate.
        let artifacts = load()?;
        let _ = cache.set(artifacts);
    }
    Ok(())
}

pub(crate) fn prepare(directory: &Path) -> CoreResult<()> {
    prepare_with(&ARTIFACTS, || {
        #[cfg(target_os = "android")]
        {
            from_directory(directory)
        }
        #[cfg(not(target_os = "android"))]
        {
            let _ = directory;
            manifest()?
                .artifacts
                .into_iter()
                .map(|entry| {
                    let bytes = decode(&entry, embedded(&entry.id))?;
                    Ok((entry.id, bytes))
                })
                .collect::<CoreResult<Vec<_>>>()
                .map(Artifacts)
        }
    })
}

pub(crate) fn get(id: &str) -> CoreResult<&'static [u8]> {
    #[cfg(not(target_os = "android"))]
    prepare(Path::new(""))?;
    ARTIFACTS
        .get()
        .and_then(|artifacts| artifacts.0.iter().find(|(key, _)| key == id))
        .map(|(_, bytes)| bytes.as_ref())
        .ok_or_else(|| integrity(id, "执行产物尚未准备或标识无效。"))
}

#[cfg(test)]
mod tests {
    include!("bundled_servers/tests.rs");
}
