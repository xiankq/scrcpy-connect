//! Private atomic writes retain ownership of the temporary file across awaits.
use crate::{CoreError, CoreResult};
use std::{
    fs::File,
    io,
    path::{Path, PathBuf},
};
use tokio::{fs, io::AsyncWriteExt};

struct Temporary {
    path: PathBuf,
    file: File,
    committed: bool,
}

impl Temporary {
    fn create(path: PathBuf) -> io::Result<Self> {
        let mut options = std::fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let file = options.open(&path)?;
        Ok(Self {
            path,
            file,
            committed: false,
        })
    }

    async fn publish(mut self, path: &Path, bytes: &[u8]) -> CoreResult<()> {
        let mut output = fs::File::from_std(self.file.try_clone()?);
        output.write_all(bytes).await?;
        // Tokio may have only accepted the final buffer. flush propagates its
        // deferred write error; sync_all alone does not report that error.
        output.flush().await?;
        output.sync_all().await?;
        drop(output);
        // Once dispatched, rename may finish even if its awaiting Future is
        // cancelled. Cleanup only owns the temporary path, never the destination.
        fs::rename(&self.path, path).await?;
        self.committed = true;
        Ok(())
    }

    #[cfg(unix)]
    fn owns_path(&self) -> bool {
        use std::os::unix::fs::MetadataExt;
        self.file
            .metadata()
            .ok()
            .zip(std::fs::symlink_metadata(&self.path).ok())
            .is_some_and(|(held, named)| held.dev() == named.dev() && held.ino() == named.ino())
    }

    #[cfg(windows)]
    fn owns_path(&self) -> bool {
        use std::os::windows::fs::OpenOptionsExt;
        // Read attributes without following a replacement reparse point.
        let named = std::fs::OpenOptions::new()
            .access_mode(0x80) // FILE_READ_ATTRIBUTES
            .custom_flags(0x00200000) // FILE_FLAG_OPEN_REPARSE_POINT
            .open(&self.path);
        named
            .ok()
            .and_then(|named| file_id(&self.file).zip(file_id(&named)))
            .is_some_and(|(held, named)| held == named)
    }

    #[cfg(not(any(unix, windows)))]
    fn owns_path(&self) -> bool {
        false
    }
}

#[cfg(windows)]
fn file_id(file: &File) -> Option<(u64, [u8; 16])> {
    use std::{ffi::c_void, os::windows::io::AsRawHandle};
    #[repr(C)]
    struct FileIdInfo {
        volume: u64,
        id: [u8; 16],
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetFileInformationByHandleEx(
            handle: *mut c_void,
            class: i32,
            information: *mut c_void,
            size: u32,
        ) -> i32;
    }
    // FILE_ID_INFO uses 128-bit identities, including on ReFS where the legacy
    // 64-bit file index is not guaranteed unique. Stable std lacks this API.
    let mut info = FileIdInfo {
        volume: 0,
        id: [0; 16],
    };
    // SAFETY: File keeps the handle live, and the writable repr(C) buffer has
    // the FILE_ID_INFO layout and size required by FileIdInfo.
    (unsafe {
        GetFileInformationByHandleEx(
            file.as_raw_handle(),
            18, // FileIdInfo
            (&mut info as *mut FileIdInfo).cast(),
            std::mem::size_of::<FileIdInfo>() as u32,
        )
    } != 0)
        .then_some((info.volume, info.id))
}

impl Drop for Temporary {
    fn drop(&mut self) {
        if !self.committed && self.owns_path() {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}

pub(crate) async fn write(path: &Path, bytes: &[u8]) -> CoreResult<()> {
    let temporary = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    // Creation may finish after its awaiting Future is dropped. Install the
    // owner inside the blocking task so even that unclaimed result cleans up.
    let temporary = tokio::task::spawn_blocking(move || Temporary::create(temporary))
        .await
        .map_err(|error| CoreError::new("io_error", error.to_string()))??;
    temporary.publish(path, bytes).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn publishes_private_file_and_cleans_failed_rename() {
        let root = tempfile::tempdir().unwrap();
        let destination = root.path().join("record.json");
        write(&destination, b"first").await.unwrap();
        write(&destination, b"replacement").await.unwrap();
        assert_eq!(std::fs::read(&destination).unwrap(), b"replacement");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&destination)
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
        let directory = root.path().join("directory");
        std::fs::create_dir(&directory).unwrap();
        assert!(write(&directory, b"must not publish").await.is_err());
        assert!(directory.is_dir());
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 2);
    }

    #[test]
    fn dropping_owner_keeps_a_replacement_at_the_temporary_path() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("owned.tmp");
        let temporary = Temporary::create(path.clone()).unwrap();
        let retained = root.path().join("retained");
        std::fs::rename(&path, &retained).unwrap();
        std::fs::write(&path, b"someone else's file").unwrap();
        drop(temporary);
        assert_eq!(std::fs::read(&path).unwrap(), b"someone else's file");
        assert!(retained.is_file());
    }

    #[test]
    fn cancelling_queued_creation_cleans_its_unclaimed_file() {
        use std::{future::Future, sync::mpsc, task::Poll, time::Duration};
        let root = tempfile::tempdir().unwrap();
        let destination = root.path().join("record.json");
        std::fs::write(&destination, b"original").unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .max_blocking_threads(1)
            .build()
            .unwrap();
        let (entered, waiting) = mpsc::channel();
        let (release, released) = mpsc::channel();
        let blocker = runtime.spawn_blocking(move || {
            entered.send(()).unwrap();
            released.recv().unwrap();
        });
        waiting.recv_timeout(Duration::from_secs(2)).unwrap();
        runtime.block_on(async {
            let mut writing = Box::pin(write(&destination, b"replacement"));
            std::future::poll_fn(|cx| {
                assert!(writing.as_mut().poll(cx).is_pending());
                Poll::Ready(())
            })
            .await;
            drop(writing);
        });
        release.send(()).unwrap();
        runtime.block_on(blocker).unwrap();
        drop(runtime); // Wait for the queued creation and its discarded owner.
        assert_eq!(std::fs::read(&destination).unwrap(), b"original");
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    }

    #[test]
    fn cancelling_a_pending_write_removes_only_its_temporary() {
        use std::{future::Future, sync::mpsc, task::Poll, time::Duration};
        let root = tempfile::tempdir().unwrap();
        let destination = root.path().join("record.json");
        std::fs::write(&destination, b"original").unwrap();
        let temporary = Temporary::create(root.path().join("owned.tmp")).unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .max_blocking_threads(1)
            .build()
            .unwrap();
        let (entered, waiting) = mpsc::channel();
        let (release, released) = mpsc::channel();
        let blocker = runtime.spawn_blocking(move || {
            entered.send(()).unwrap();
            released.recv().unwrap();
        });
        waiting.recv_timeout(Duration::from_secs(2)).unwrap();
        runtime.block_on(async {
            let mut writing = Box::pin(temporary.publish(&destination, b"replacement"));
            std::future::poll_fn(|cx| {
                assert!(writing.as_mut().poll(cx).is_pending());
                Poll::Ready(())
            })
            .await;
            drop(writing);
        });
        release.send(()).unwrap();
        runtime.block_on(blocker).unwrap();
        drop(runtime); // Wait for the already dispatched file write to finish.
        assert_eq!(std::fs::read(&destination).unwrap(), b"original");
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn failed_write_removes_temporary_and_preserves_destination() {
        const CHILD: &str = "INTEROP_PRIVATE_WRITE_LIMIT_CHILD";
        if let Some(directory) = std::env::var_os(CHILD) {
            let destination = PathBuf::from(directory).join("record.json");
            // Isolated process: force a genuine write_all failure, without
            // changing the test runner's limits or requiring a full disk.
            unsafe {
                libc::signal(libc::SIGXFSZ, libc::SIG_IGN);
                let mut limit = std::mem::zeroed::<libc::rlimit>();
                assert_eq!(libc::getrlimit(libc::RLIMIT_FSIZE, &mut limit), 0);
                limit.rlim_cur = 4;
                assert_eq!(libc::setrlimit(libc::RLIMIT_FSIZE, &limit), 0);
            }
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();
            assert!(runtime.block_on(write(&destination, &[1; 4096])).is_err());
            assert_eq!(std::fs::read(&destination).unwrap(), b"original");
            assert_eq!(
                std::fs::read_dir(destination.parent().unwrap())
                    .unwrap()
                    .count(),
                1
            );
            return;
        }
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("record.json"), b"original").unwrap();
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "private_file::tests::failed_write_removes_temporary_and_preserves_destination",
                "--nocapture",
            ])
            .env(CHILD, root.path())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
