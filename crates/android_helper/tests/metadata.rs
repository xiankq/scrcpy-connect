use std::{
    ffi::OsStr,
    fs,
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicUsize, Ordering},
};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "interop-helper-metadata-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self, name: impl AsRef<Path>) -> PathBuf {
        self.0.join(name)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

fn command(operation: &str, path: &Path, limit: &str) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_interop-android-helper"));
    command.args([OsStr::new(operation), path.as_os_str(), OsStr::new(limit)]);
    command
}

fn output(operation: &str, path: &Path, limit: &str) -> String {
    let output = command(operation, path, limit).output().unwrap();
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn stat_follows_links_and_lstat_preserves_link_and_large_file_size() {
    let fixture = Fixture::new();
    let path = fixture.path(OsStr::from_bytes(b"file-\xff\n"));
    let file = fs::File::create(&path).unwrap();
    file.set_len((1u64 << 32) + 19).unwrap();
    file.set_times(
        fs::FileTimes::new()
            .set_modified(std::time::UNIX_EPOCH - std::time::Duration::from_secs(42)),
    )
    .unwrap();
    let link = fixture.path("link");
    std::os::unix::fs::symlink(&path, &link).unwrap();
    let metadata = fs::metadata(&path).unwrap();
    assert_eq!(metadata.mtime(), -42);
    let expected = format!(
        "{{\"protocol\":1,\"ok\":true,\"errno\":0,\"mode\":{},\"size\":4294967315,\"modifiedSeconds\":{}}}\n",
        metadata.mode(),
        metadata.mtime()
    );
    assert_eq!(output("stat", &link, "unused"), expected);
    assert_eq!(output("lstat", &path, "unused"), expected);
    let metadata = fs::symlink_metadata(&link).unwrap();
    assert_eq!(
        output("lstat", &link, "unused"),
        format!(
            "{{\"protocol\":1,\"ok\":true,\"errno\":0,\"mode\":{},\"size\":{},\"modifiedSeconds\":{}}}\n",
            metadata.mode(),
            metadata.size(),
            metadata.mtime()
        )
    );
    assert_eq!(
        output("lstat", &fixture.path("link/"), "unused"),
        output("lstat", &link, "unused")
    );
    let missing = output("lstat", &fixture.path("absent"), "unused");
    assert_eq!(missing, "{\"protocol\":1,\"ok\":false,\"errno\":2}\n");
    assert!(!missing.contains("absent"));
}

#[test]
fn list_keeps_raw_names_and_link_metadata_and_reports_exact_truncation() {
    let fixture = Fixture::new();
    let directory = fixture.path("directory");
    fs::create_dir(&directory).unwrap();
    let file = directory.join(OsStr::from_bytes(b"x\xff\n"));
    fs::write(&file, b"abc").unwrap();
    let link = directory.join("link");
    std::os::unix::fs::symlink("missing", &link).unwrap();
    let listing = output("list", &directory, "2");
    assert!(
        listing.starts_with("{\"protocol\":1,\"entries\":["),
        "{listing}"
    );
    for (name, path) in [("78ff0a", &file), ("6c696e6b", &link)] {
        let stat = fs::symlink_metadata(path).unwrap();
        assert!(listing.contains(&format!(
            "{{\"nameHex\":\"{name}\",\"mode\":{},\"size\":{},\"modifiedSeconds\":{},\"errno\":0}}",
            stat.mode(), stat.size(), stat.mtime()
        )), "{listing}");
    }
    assert!(listing.ends_with("],\"truncated\":false,\"ok\":true,\"errno\":0}\n"));
    let truncated = output("list", &directory, "1");
    assert_eq!(truncated.matches("\"nameHex\"").count(), 1);
    assert!(truncated.ends_with("],\"truncated\":true,\"ok\":true,\"errno\":0}\n"));
    for limit in ["0", "10001", "-1", "garbage"] {
        assert_eq!(
            output("list", &directory, limit),
            "{\"protocol\":1,\"ok\":false,\"errno\":22}\n"
        );
    }
    assert!(output("list", &directory, "10000").contains("\"truncated\":false"));
    let alias = fixture.path("alias");
    std::os::unix::fs::symlink(&directory, &alias).unwrap();
    for path in [&alias, &fixture.path("alias/")] {
        let rejected = output("list", path, "10000");
        assert!(rejected.contains("\"ok\":false"), "{rejected}");
        assert!(!rejected.contains("\"errno\":0"));
    }
    assert!(output("list", &fixture.path("alias/."), "10000").contains("\"ok\":true"));
}

#[test]
fn list_keeps_entries_whose_metadata_is_not_accessible() {
    use std::os::unix::{fs::PermissionsExt, process::CommandExt};
    let fixture = Fixture::new();
    fs::set_permissions(&fixture.0, fs::Permissions::from_mode(0o755)).unwrap();
    let directory = fixture.path("directory");
    fs::create_dir(&directory).unwrap();
    fs::write(directory.join("file"), b"private").unwrap();
    // Read permission permits enumeration; missing search permission denies
    // fstatat on each child. Run unprivileged even on a root test runner.
    fs::set_permissions(&directory, fs::Permissions::from_mode(0o444)).unwrap();
    let mut child = command("list", &directory, "10000");
    if unsafe { libc::geteuid() } == 0 {
        child.uid(65534).gid(65534);
    }
    let result = child.output().unwrap();
    fs::set_permissions(&directory, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(result.status.success());
    assert!(result.stderr.is_empty());
    assert_eq!(
        String::from_utf8(result.stdout).unwrap(),
        "{\"protocol\":1,\"entries\":[{\"nameHex\":\"66696c65\",\"mode\":0,\"size\":0,\"modifiedSeconds\":0,\"errno\":13}],\"truncated\":false,\"ok\":true,\"errno\":0}\n"
    );
}

#[test]
fn list_metadata_stays_on_opened_directory_after_its_path_is_replaced() {
    use std::{io::Read, os::fd::AsRawFd, process::Stdio};
    let fixture = Fixture::new();
    let directory = fixture.path("directory");
    fs::create_dir(&directory).unwrap();
    for index in 0..512 {
        fs::write(
            directory.join(format!("{index:04}-{}", "x".repeat(200))),
            b"old",
        )
        .unwrap();
    }
    let trap = fixture.path("trap");
    fs::create_dir(&trap).unwrap();
    let mut child = command("list", &directory, "10000")
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdout = child.stdout.take().unwrap();
    assert!(unsafe { libc::fcntl(stdout.as_raw_fd(), libc::F_SETPIPE_SZ, 4096) } >= 4096);
    let mut first = [0];
    stdout.read_exact(&mut first).unwrap();
    assert_eq!(&first, b"{");
    // Output exceeds the pipe capacity, so some child metadata has yet to be
    // read. Replacing the original path must not redirect those lookups.
    fs::rename(&directory, fixture.path("moved")).unwrap();
    std::os::unix::fs::symlink(&trap, &directory).unwrap();
    let mut remaining = String::new();
    stdout.read_to_string(&mut remaining).unwrap();
    assert!(child.wait().unwrap().success());
    assert_eq!(remaining.matches("\"nameHex\"").count(), 512);
    assert_eq!(remaining.matches("\"size\":3").count(), 512);
    assert_eq!(remaining.matches("\"errno\":0").count(), 513);
    assert!(remaining.ends_with("],\"truncated\":false,\"ok\":true,\"errno\":0}\n"));
}

#[test]
fn metadata_dispatch_preserves_existing_rename_contract() {
    let fixture = Fixture::new();
    let source = fixture.path("source");
    let destination = fixture.path("destination");
    fs::write(&source, b"new").unwrap();
    fs::write(&destination, b"old").unwrap();
    let invoke = |operation| {
        let result = Command::new(env!("CARGO_BIN_EXE_interop-android-helper"))
            .arg(operation)
            .arg(&source)
            .arg(&destination)
            .output()
            .unwrap();
        assert!(result.status.success());
        String::from_utf8(result.stdout).unwrap()
    };
    assert_eq!(
        invoke("rename-no-replace"),
        "{\"protocol\":1,\"ok\":false,\"errno\":17}\n"
    );
    assert_eq!(fs::read(&source).unwrap(), b"new");
    assert_eq!(fs::read(&destination).unwrap(), b"old");
    assert_eq!(
        invoke("publish-replace"),
        "{\"protocol\":1,\"ok\":true,\"errno\":0}\n"
    );
    assert!(!source.exists());
    assert_eq!(fs::read(&destination).unwrap(), b"new");
}

#[test]
fn list_preserves_ten_thousand_entry_budget_and_reports_overflow() {
    let fixture = Fixture::new();
    for index in 0..10_001 {
        fs::File::create(fixture.path(format!("file-{index}"))).unwrap();
    }
    for limit in [4096, 10_000] {
        let result = output("list", &fixture.0, &limit.to_string());
        assert_eq!(result.matches("\"nameHex\"").count(), limit);
        assert!(result.ends_with("],\"truncated\":true,\"ok\":true,\"errno\":0}\n"));
    }
}
