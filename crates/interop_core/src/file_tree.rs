//! A bounded selection snapshot. Links and special files are records, never traversal edges.
use crate::{
    CoreError, CoreResult,
    files::{SourceStamp, local_stamp, metadata_stamp},
    model::{quote, remote_path},
};
use interop_adb::{Client, OperationOptions, sync::RemotePath};
use std::{collections::HashSet, path::Path};

pub(crate) const MAX_ENTRIES: usize = 10_000;
const MAX_DEPTH: usize = 64;
const MAX_PATH_BYTES: usize = 16 * 1024 * 1024;

pub(crate) struct Entry {
    pub source: String,
    pub destination: String,
    pub kind: &'static str,
    pub parent: Option<usize>,
    pub stamp: Option<SourceStamp>,
    pub error: Option<CoreError>,
    depth: usize,
}
pub(crate) struct Selection {
    pub entries: Vec<Entry>,
    bytes: usize,
    destinations: HashSet<String>,
}
impl Selection {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
            bytes: 0,
            destinations: HashSet::new(),
        }
    }
    fn append(&mut self, entry: Entry) -> CoreResult<usize> {
        self.bytes = self
            .bytes
            .saturating_add(entry.source.len() + entry.destination.len());
        if self.entries.len() >= MAX_ENTRIES
            || entry.depth > MAX_DEPTH
            || self.bytes > MAX_PATH_BYTES
        {
            return Err(CoreError::new(
                "tree_limit",
                "目录选择超过 10000 项、64 层或 16 MiB 路径上限；请分批选择。",
            ));
        }
        if !self.destinations.insert(entry.destination.clone()) {
            return Err(CoreError::new(
                "duplicate_destination",
                "批任务中不能重复写入同一目标。",
            ));
        }
        let index = self.entries.len();
        self.entries.push(entry);
        Ok(index)
    }
    pub async fn local(&mut self, source: String, destination: String) -> CoreResult<()> {
        let start = self.append(Entry {
            source,
            destination,
            kind: "pending",
            parent: None,
            stamp: None,
            error: None,
            depth: 0,
        })?;
        let mut next = start;
        while next < self.entries.len() {
            let index = next;
            next += 1;
            let entry = &self.entries[index];
            let metadata = match tokio::fs::symlink_metadata(&entry.source).await {
                Ok(metadata) => metadata,
                Err(error) => {
                    self.entries[index].kind = "failed";
                    self.entries[index].error = Some(error.into());
                    continue;
                }
            };
            if metadata.file_type().is_symlink() {
                self.entries[index].kind = "symlink";
                continue;
            }
            if metadata.is_file() {
                self.entries[index].kind = "file";
                match local_stamp(&self.entries[index].source).await {
                    Ok(stamp) => self.entries[index].stamp = Some(stamp),
                    Err(error) => self.entries[index].error = Some(error),
                }
                continue;
            }
            if !metadata.is_dir() {
                self.entries[index].kind = "unsupported";
                continue;
            }
            self.entries[index].kind = "directory";
            self.entries[index].stamp = Some(metadata_stamp(&metadata)?);
            let source = self.entries[index].source.clone();
            let destination = self.entries[index].destination.clone();
            let depth = self.entries[index].depth + 1;
            let mut directory = match tokio::fs::read_dir(&source).await {
                Ok(directory) => directory,
                Err(error) => {
                    self.entries[index].error = Some(error.into());
                    continue;
                }
            };
            loop {
                let child = match directory.next_entry().await {
                    Ok(Some(child)) => child,
                    Ok(None) => break,
                    Err(error) => {
                        self.entries[index].error = Some(error.into());
                        break;
                    }
                };
                let Some(name) = child.file_name().to_str().map(str::to_owned) else {
                    self.entries[index].error = Some(CoreError::new(
                        "invalid_filename",
                        "目录包含无法表示为有效文字的文件名；该目录未完整传输。",
                    ));
                    continue;
                };
                self.append(Entry {
                    source: child.path().to_string_lossy().into_owned(),
                    destination: remote_path(&format!(
                        "{}/{}",
                        destination.trim_end_matches('/'),
                        name
                    ))
                    .and_then(|path| {
                        join("/", &name)?;
                        Ok(path)
                    })?,
                    kind: "pending",
                    parent: Some(index),
                    stamp: None,
                    error: None,
                    depth,
                })?;
            }
        }
        Ok(())
    }
    pub async fn remote(
        &mut self,
        client: &Client,
        source: String,
        destination: String,
    ) -> CoreResult<()> {
        let start = self.append(Entry {
            source,
            destination,
            kind: "pending",
            parent: None,
            stamp: None,
            error: None,
            depth: 0,
        })?;
        let mut next = start;
        while next < self.entries.len() {
            let index = next;
            next += 1;
            if self.entries[index].kind != "pending" {
                continue;
            }
            let source = self.entries[index].source.clone();
            let mut sync = client.sync(OperationOptions::default()).await?;
            let stat = remote_stat(client, &source).await;
            let stat = match stat {
                Ok(stat) => stat,
                Err(error) => {
                    self.entries[index].kind = "failed";
                    self.entries[index].error = Some(error);
                    continue;
                }
            };
            match stat.mode & 0o170000 {
                0o120000 => {
                    self.entries[index].kind = "symlink";
                    continue;
                }
                0o100000 => {
                    self.entries[index].kind = "file";
                    self.entries[index].stamp = Some(stat.into());
                    continue;
                }
                0o040000 => {
                    self.entries[index].kind = "directory";
                    self.entries[index].stamp = Some(stat.into());
                }
                _ => {
                    self.entries[index].kind = "unsupported";
                    continue;
                }
            }
            let destination = self.entries[index].destination.clone();
            let depth = self.entries[index].depth + 1;
            // One directory is also bounded; no shell find or unbounded stdout.
            let children = match sync
                .list(
                    &RemotePath::new(&source)?,
                    MAX_ENTRIES - self.entries.len() + 1,
                )
                .await
            {
                Ok(children) => children
                    .into_iter()
                    .map(|child| (child.name, Ok(child.stat)))
                    .collect(),
                Err(_) => {
                    match shell_children(client, &source, MAX_ENTRIES - self.entries.len() + 1)
                        .await
                    {
                        Ok(children) => children,
                        Err(error) => {
                            self.entries[index].error = Some(error);
                            continue;
                        }
                    }
                }
            };
            for (child_name, child_stat) in children {
                if child_name == b"." || child_name == b".." {
                    continue;
                }
                let name = match String::from_utf8(child_name) {
                    Ok(name)
                        if !name.contains('/') && !name.contains('\\') && !name.contains('\0') =>
                    {
                        name
                    }
                    _ => {
                        self.entries[index].error = Some(CoreError::new(
                            "invalid_filename",
                            "目录包含不能安全表示的文件名；该目录未完整传输。",
                        ));
                        continue;
                    }
                };
                let child_source =
                    remote_path(&format!("{}/{}", source.trim_end_matches('/'), name))?;
                let child_destination = join(&destination, &name)?;
                let stat = match child_stat {
                    Ok(stat) => stat,
                    Err(error) => {
                        self.append(Entry {
                            source: child_source,
                            destination: child_destination,
                            kind: "failed",
                            parent: Some(index),
                            stamp: None,
                            error: Some(error),
                            depth,
                        })?;
                        continue;
                    }
                };
                let kind = match stat.mode & 0o170000 {
                    0o040000 => "pending",
                    0o100000 => "file",
                    0o120000 => "symlink",
                    _ => "unsupported",
                };
                self.append(Entry {
                    source: child_source,
                    destination: child_destination,
                    kind,
                    parent: Some(index),
                    stamp: (kind == "file").then(|| stat.into()),
                    error: None,
                    depth,
                })?;
            }
        }
        Ok(())
    }
}
fn join(parent: &str, name: &str) -> CoreResult<String> {
    if name.is_empty()
        || matches!(name, "." | "..")
        || name.contains('/')
        || name.contains('\\')
        || name.contains('\0')
    {
        return Err(CoreError::new(
            "invalid_filename",
            "文件名无法安全映射到目标目录。",
        ));
    }
    Ok(Path::new(parent).join(name).to_string_lossy().into_owned())
}
pub(crate) async fn remote_stat(
    client: &Client,
    path: &str,
) -> CoreResult<interop_adb::sync::FileStat> {
    let mut sync = client.sync(OperationOptions::default()).await?;
    match sync.lstat(&RemotePath::new(path)?).await {
        Ok(stat) => Ok(stat),
        // Some AOSP policies deny adbd getattr on shell-created symlinks.
        // The ordinary shell service can report their actual lstat metadata;
        // no root, permission changes, or follow-link option are involved.
        Err(_) => shell_stat(client, path).await,
    }
}

type ChildStats = Vec<(Vec<u8>, CoreResult<interop_adb::sync::FileStat>)>;
async fn shell_children(client: &Client, path: &str, limit: usize) -> CoreResult<ChildStats> {
    let result = client
        .shell(
            &format!("find {} -mindepth 1 -maxdepth 1 -print0", quote(path)?),
            MAX_PATH_BYTES,
            OperationOptions::default(),
        )
        .await?;
    if result.exit_code != Some(0) {
        return Err(CoreError::new(
            "directory_read_failed",
            String::from_utf8_lossy(&result.stderr).into_owned(),
        ));
    }
    let mut children = Vec::new();
    for child in result
        .stdout
        .split(|byte| *byte == 0)
        .filter(|child| !child.is_empty())
    {
        if children.len() >= limit {
            return Err(CoreError::new(
                "tree_limit",
                "目录项目数量超过上限，请分批选择。",
            ));
        }
        let name = child
            .rsplit(|byte| *byte == b'/')
            .next()
            .unwrap_or_default()
            .to_vec();
        let stat = match std::str::from_utf8(child) {
            Ok(path) => shell_stat(client, path).await,
            Err(_) => Err(CoreError::new(
                "invalid_filename",
                "不能安全表示此文件名；未传输此项。",
            )),
        };
        children.push((name, stat));
    }
    Ok(children)
}
async fn shell_stat(client: &Client, path: &str) -> CoreResult<interop_adb::sync::FileStat> {
    let result = client
        .shell(
            &format!("stat -c '%f:%s:%Y' -- {}", quote(path)?),
            4096,
            OperationOptions::default(),
        )
        .await?;
    if result.exit_code != Some(0) {
        let message = String::from_utf8_lossy(&result.stderr).into_owned();
        return Err(CoreError::new(
            if message.contains("No such file") {
                "source_changed"
            } else {
                "remote_stat_failed"
            },
            message,
        ));
    }
    let output = std::str::from_utf8(&result.stdout)
        .map_err(|_| CoreError::new("invalid_metadata", "文件元数据格式无效。"))?;
    let fields = output.trim().split(':').collect::<Vec<_>>();
    let parse = || -> Option<interop_adb::sync::FileStat> {
        Some(interop_adb::sync::FileStat {
            mode: u32::from_str_radix(fields.first()?, 16).ok()?,
            size: fields.get(1)?.parse().ok()?,
            modified_seconds: fields.get(2)?.parse().ok()?,
        })
    };
    parse()
        .filter(|_| fields.len() == 3)
        .ok_or_else(|| CoreError::new("invalid_metadata", "文件元数据格式无效。"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn selection_keeps_empty_directories_and_never_traverses_a_link_cycle() {
        let directory = tempfile::tempdir().unwrap();
        tokio::fs::create_dir(directory.path().join("empty"))
            .await
            .unwrap();
        tokio::fs::write(directory.path().join("payload"), b"contents")
            .await
            .unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(directory.path(), directory.path().join("cycle")).unwrap();
        let mut selection = Selection::new();
        selection
            .local(
                directory.path().to_str().unwrap().into(),
                "/remote/root".into(),
            )
            .await
            .unwrap();
        assert!(
            selection
                .entries
                .iter()
                .any(|entry| entry.kind == "directory" && entry.destination.ends_with("/empty"))
        );
        assert!(
            selection
                .entries
                .iter()
                .any(|entry| entry.kind == "file" && entry.stamp.as_ref().unwrap().size == 8)
        );
        #[cfg(unix)]
        assert_eq!(
            selection
                .entries
                .iter()
                .filter(|entry| entry.kind == "symlink")
                .count(),
            1
        );
        assert!(selection.entries.len() <= 4);
    }
    #[test]
    fn excessive_depth_and_escaping_names_are_rejected() {
        assert!(join("/target", "../outside").is_err());
        assert!(join("/target", "a\\b").is_err());
        let mut selection = Selection::new();
        let error = selection
            .append(Entry {
                source: "/s".into(),
                destination: "/d".into(),
                kind: "directory",
                parent: None,
                stamp: None,
                error: None,
                depth: MAX_DEPTH + 1,
            })
            .unwrap_err();
        assert_eq!(error.code, "tree_limit");
    }
}
