use super::*;

async fn replace_first(path: String, pem: &str) -> Result<IdentityCommitReceipt, String> {
    replace(path, pem.into(), Some(EXPECTED_FINGERPRINT.into())).await
}

#[tokio::test]
async fn inspection_does_not_create_a_missing_key() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().canonicalize().unwrap().join("missing.pem");
    assert!(
        inspect(path.to_str().unwrap().into())
            .await
            .unwrap()
            .is_none()
    );
    assert!(!path.exists());
    assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 0);
}

#[cfg(any(target_os = "linux", target_os = "android"))]
#[tokio::test]
async fn identity_access_needs_only_search_permission_on_ancestors() {
    use std::os::unix::fs::PermissionsExt;

    struct SearchOnlyAncestor(PathBuf);
    impl Drop for SearchOnlyAncestor {
        fn drop(&mut self) {
            fs::set_permissions(&self.0, fs::Permissions::from_mode(0o700)).unwrap();
        }
    }

    let root = tempfile::tempdir().unwrap();
    let ancestor = root.path().canonicalize().unwrap().join("search-only");
    let owned = ancestor.join("private");
    fs::create_dir_all(&owned).unwrap();
    let _restore = SearchOnlyAncestor(ancestor.clone());
    fs::set_permissions(&ancestor, fs::Permissions::from_mode(0o100)).unwrap();
    // A sandbox may allow lookup of a known private path but deny listing its ancestors.
    if fs::read_dir(&ancestor).is_ok() {
        // Privileged test runners bypass mode bits and cannot reproduce this restriction.
        return;
    }
    let path = owned.join("identity.pem").to_str().unwrap().to_owned();
    assert!(inspect(path.clone()).await.unwrap().is_none());
    let first = replace(path.clone(), VALID_ONE.into(), None).await.unwrap();
    assert_eq!(first.state, IdentityCommitState::Committed);
    assert_eq!(inspect(path.clone()).await.unwrap(), first.identity);
    let changed = replace_first(path.clone(), VALID_TWO).await.unwrap();
    assert_eq!(changed.state, IdentityCommitState::Committed);
    assert_eq!(inspect(path).await.unwrap(), changed.identity);
}

fn path(directory: &tempfile::TempDir) -> std::path::PathBuf {
    directory
        .path()
        .canonicalize()
        .unwrap()
        .join("identity.pem")
}

#[test]
fn validation_matches_legacy_fingerprint_and_checks_real_rsa_parameters() {
    let first = validate(VALID_ONE).unwrap();
    assert_eq!(first.fingerprint, EXPECTED_FINGERPRINT);
    assert_eq!(first.fingerprint_algorithm, "sha256");
    assert_eq!(first.fingerprint_input, "adb-public-key-interop-v1");
    assert_eq!((first.bits, first.exponent), (2048, 65537));
    assert_eq!(validate(VALID_ONE_PKCS1).unwrap(), first);
    for invalid in [INVALID_SIZE, INVALID_EXPONENT, "broken"] {
        assert_eq!(validate(invalid).unwrap_err(), "adb_identity_invalid");
    }
    assert_eq!(
        validate(&"é".repeat(17_000)).unwrap_err(),
        "adb_identity_size_limit"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn a_valid_long_file_name_does_not_overflow_the_lock_name() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory
        .path()
        .canonicalize()
        .unwrap()
        .join("k".repeat(250));
    let receipt = replace(path.to_str().unwrap().into(), VALID_ONE.into(), None)
        .await
        .unwrap();
    assert_eq!(receipt.state, IdentityCommitState::Committed);
    assert_eq!(
        inspect(path.to_str().unwrap().into()).await.unwrap(),
        receipt.identity
    );
}

#[tokio::test]
async fn installation_is_explicit_and_replacement_compares_the_previous_fingerprint() {
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory);
    let name = path.to_str().unwrap().to_owned();
    let first = replace(name.clone(), VALID_ONE.into(), None).await.unwrap();
    assert_eq!(first.state, IdentityCommitState::Committed);
    assert_eq!(inspect(name.clone()).await.unwrap(), first.identity);
    let before = fs::read(&path).unwrap();
    let conflict = replace(name.clone(), VALID_TWO.into(), None).await.unwrap();
    assert_eq!(conflict.state, IdentityCommitState::Unchanged);
    assert_eq!(conflict.error.as_deref(), Some("adb_identity_conflict"));
    assert_eq!(fs::read(&path).unwrap(), before);
    let same = replace_first(name.clone(), VALID_ONE_PKCS1).await.unwrap();
    assert_eq!(same.state, IdentityCommitState::Unchanged);
    assert!(same.error.is_none());
    assert_eq!(fs::read(&path).unwrap(), before);
    let changed = replace_first(name.clone(), VALID_TWO).await.unwrap();
    assert_eq!(changed.state, IdentityCommitState::Committed);
    assert_eq!(changed.identity, Some(validate(VALID_TWO).unwrap()));
    assert_eq!(inspect(name).await.unwrap(), changed.identity);
    assert!(fs::read_dir(directory.path()).unwrap().all(|entry| {
        !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .ends_with(".tmp")
    }));
}

#[tokio::test]
async fn competing_replacements_do_not_both_commit_from_the_same_baseline() {
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory).to_str().unwrap().to_owned();
    replace(path.clone(), VALID_ONE.into(), None).await.unwrap();
    let (first, second) = tokio::join!(
        replace_first(path.clone(), VALID_TWO),
        replace_first(path.clone(), VALID_TWO),
    );
    let states = [first.unwrap().state, second.unwrap().state];
    assert_eq!(
        states
            .iter()
            .filter(|state| **state == IdentityCommitState::Committed)
            .count(),
        1
    );
    assert_eq!(
        states
            .iter()
            .filter(|state| **state == IdentityCommitState::Unchanged)
            .count(),
        1
    );
    assert_eq!(
        inspect(path).await.unwrap(),
        Some(validate(VALID_TWO).unwrap())
    );
}

#[test]
fn competing_writer_waits_until_the_first_publication_has_finished() {
    use std::{sync::mpsc, time::Duration};
    struct PausedPublication {
        entered: mpsc::Sender<()>,
        resume: mpsc::Receiver<()>,
    }
    impl IdentityCommitIo for PausedPublication {
        fn publish(
            &self,
            directory: &IdentityDirectory,
            temporary: &OsStr,
            target: &OsStr,
            replace: bool,
        ) -> std::io::Result<()> {
            self.entered.send(()).unwrap();
            self.resume.recv().unwrap();
            directory.publish(temporary, target, replace)
        }
        fn sync_directory(&self, directory: &IdentityDirectory) -> std::io::Result<()> {
            FilesystemCommit.sync_directory(directory)
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory);
    replace_blocking(&path, VALID_ONE, None, &FilesystemCommit).unwrap();
    let (entered, pending) = mpsc::channel();
    let (resume, suspended) = mpsc::channel();
    let first_path = path.clone();
    let first = std::thread::spawn(move || {
        replace_blocking(
            &first_path,
            VALID_TWO,
            Some(EXPECTED_FINGERPRINT),
            &PausedPublication {
                entered,
                resume: suspended,
            },
        )
        .unwrap()
    });
    pending.recv_timeout(Duration::from_secs(5)).unwrap();
    let (started, starting) = mpsc::channel();
    let (finished, completion) = mpsc::channel();
    let second = std::thread::spawn(move || {
        started.send(()).unwrap();
        let receipt = replace_blocking(
            &path,
            VALID_TWO,
            Some(EXPECTED_FINGERPRINT),
            &FilesystemCommit,
        )
        .unwrap();
        finished.send(receipt).unwrap();
    });
    starting.recv_timeout(Duration::from_secs(5)).unwrap();
    let early = completion.recv_timeout(Duration::from_millis(100));
    // 先放行、回收线程，再断言，避免回归失败把持锁线程永久留在夹具内。
    resume.send(()).unwrap();
    assert_eq!(first.join().unwrap().state, IdentityCommitState::Committed);
    let result = early
        .as_ref()
        .ok()
        .cloned()
        .unwrap_or_else(|| completion.recv_timeout(Duration::from_secs(5)).unwrap());
    second.join().unwrap();
    assert!(early.is_err());
    assert_eq!(result.state, IdentityCommitState::Unchanged);
    assert_eq!(result.error.as_deref(), Some("adb_identity_conflict"));
}

#[tokio::test]
async fn preparation_and_explicit_first_install_share_one_complete_identity() {
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory).to_str().unwrap().to_owned();
    let (prepared, imported) = tokio::join!(
        prepare(path.clone()),
        replace(path.clone(), VALID_ONE.into(), None)
    );
    let prepared = info(&prepared.unwrap()).unwrap();
    let imported = imported.unwrap();
    assert_ne!(imported.state, IdentityCommitState::Unknown);
    assert_eq!(inspect(path).await.unwrap(), Some(prepared.clone()));
    if imported.state == IdentityCommitState::Committed {
        assert_eq!(prepared.fingerprint, EXPECTED_FINGERPRINT);
    }
}

#[tokio::test]
async fn malformed_existing_key_and_invalid_input_never_replace_original_bytes() {
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory);
    fs::write(&path, "broken-original").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    }
    let name = path.to_str().unwrap().to_owned();
    assert!(
        inspect(name.clone())
            .await
            .unwrap_err()
            .starts_with("adb_identity_invalid")
    );
    assert!(
        replace(name.clone(), VALID_ONE.into(), None)
            .await
            .unwrap_err()
            .starts_with("adb_identity_invalid")
    );
    assert_eq!(fs::read(&path).unwrap(), b"broken-original");
    assert_eq!(
        replace(name, INVALID_EXPONENT.into(), None)
            .await
            .unwrap_err(),
        "adb_identity_invalid"
    );
    assert_eq!(fs::read(&path).unwrap(), b"broken-original");
}

enum Failure {
    BeforePublish,
    LostPublishReceipt,
    UnreadableOutcome,
    DirectorySync,
}
impl IdentityCommitIo for Failure {
    fn publish(
        &self,
        directory: &IdentityDirectory,
        temporary: &OsStr,
        target: &OsStr,
        replace: bool,
    ) -> std::io::Result<()> {
        if matches!(self, Self::BeforePublish) {
            return Err(std::io::Error::other("夹具：发布前失败"));
        }
        directory.publish(temporary, target, replace)?;
        if matches!(self, Self::UnreadableOutcome) {
            let mut file = directory.open_file(target, false, true)?;
            file.set_len(0)?;
            file.write_all(b"unreadable-outcome")?;
            file.sync_all()?;
        }
        if matches!(self, Self::LostPublishReceipt | Self::UnreadableOutcome) {
            return Err(std::io::Error::other("夹具：发布回执丢失"));
        }
        Ok(())
    }
    fn sync_directory(&self, directory: &IdentityDirectory) -> std::io::Result<()> {
        if matches!(self, Self::DirectorySync) {
            return Err(std::io::Error::other("夹具：目录刷新失败"));
        }
        FilesystemCommit.sync_directory(directory)
    }
}

#[test]
fn commit_failure_receipts_distinguish_unchanged_committed_and_unknown() {
    for (failure, expected) in [
        (Failure::BeforePublish, IdentityCommitState::Unchanged),
        (Failure::LostPublishReceipt, IdentityCommitState::Committed),
        (Failure::UnreadableOutcome, IdentityCommitState::Unknown),
        (Failure::DirectorySync, IdentityCommitState::Unknown),
    ] {
        let directory = tempfile::tempdir().unwrap();
        let path = path(&directory);
        replace_blocking(&path, VALID_ONE, None, &FilesystemCommit).unwrap();
        let before = fs::read(&path).unwrap();
        let receipt =
            replace_blocking(&path, VALID_TWO, Some(EXPECTED_FINGERPRINT), &failure).unwrap();
        assert_eq!(receipt.state, expected);
        match failure {
            Failure::BeforePublish => assert_eq!(fs::read(&path).unwrap(), before),
            Failure::LostPublishReceipt => assert_eq!(
                load(&path).unwrap().as_ref().map(info).transpose().unwrap(),
                receipt.identity
            ),
            Failure::DirectorySync => {
                assert_eq!(receipt.identity, Some(validate(VALID_TWO).unwrap()));
                let retry = replace_blocking(
                    &path,
                    VALID_TWO,
                    Some(EXPECTED_FINGERPRINT),
                    &FilesystemCommit,
                )
                .unwrap();
                assert_eq!(retry.state, IdentityCommitState::Unchanged);
                assert_eq!(retry.error.as_deref(), Some("adb_identity_conflict"));
            }
            Failure::UnreadableOutcome => {
                assert!(receipt.identity.is_none());
                assert_eq!(fs::read(&path).unwrap(), b"unreadable-outcome");
                assert!(
                    replace_blocking(
                        &path,
                        VALID_ONE,
                        Some(EXPECTED_FINGERPRINT),
                        &FilesystemCommit
                    )
                    .is_err()
                );
                assert_eq!(fs::read(&path).unwrap(), b"unreadable-outcome");
            }
        }
    }
}

#[cfg(unix)]
#[tokio::test]
async fn inspection_and_import_refuse_links_and_keep_mode_0600() {
    use std::os::unix::fs::{PermissionsExt, symlink};
    let directory = tempfile::tempdir().unwrap();
    let path = path(&directory);
    let name = path.to_str().unwrap().to_owned();
    replace(name.clone(), VALID_ONE.into(), None).await.unwrap();
    let linked = directory.path().join("linked.pem");
    symlink(&path, &linked).unwrap();
    assert!(inspect(linked.to_str().unwrap().into()).await.is_err());
    assert!(
        replace_first(linked.to_str().unwrap().into(), VALID_TWO)
            .await
            .is_err()
    );
    assert_eq!(
        fs::metadata(&path).unwrap().permissions().mode() & 0o777,
        0o600
    );
    fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
    let before = fs::read(&path).unwrap();
    assert_eq!(
        inspect(name.clone()).await.unwrap_err(),
        "adb_identity_permissions"
    );
    assert_eq!(
        replace_first(name, VALID_TWO).await.unwrap_err(),
        "adb_identity_permissions"
    );
    assert_eq!(fs::read(&path).unwrap(), before);
    let alias = directory.path().join("alias");
    symlink(directory.path(), &alias).unwrap();
    assert!(
        inspect(alias.join("identity.pem").to_str().unwrap().into())
            .await
            .is_err()
    );
    assert!(
        replace(
            alias.join("other.pem").to_str().unwrap().into(),
            VALID_ONE.into(),
            None
        )
        .await
        .is_err()
    );
    assert!(!directory.path().join("other.pem").exists());
}

#[cfg(unix)]
#[test]
fn opened_directory_cannot_be_redirected_during_publication() {
    use std::os::unix::fs::symlink;
    struct Redirect<'a>(&'a Path, &'a Path, &'a Path);
    impl IdentityCommitIo for Redirect<'_> {
        fn publish(
            &self,
            directory: &IdentityDirectory,
            temporary: &OsStr,
            target: &OsStr,
            replace: bool,
        ) -> std::io::Result<()> {
            fs::rename(self.0, self.1)?;
            symlink(self.2, self.0)?;
            directory.publish(temporary, target, replace)
        }
        fn sync_directory(&self, directory: &IdentityDirectory) -> std::io::Result<()> {
            FilesystemCommit.sync_directory(directory)
        }
    }
    let root = tempfile::tempdir().unwrap();
    let canonical = root.path().canonicalize().unwrap();
    let directory = canonical.join("owned");
    let moved = canonical.join("moved");
    let other = canonical.join("other");
    fs::create_dir(&directory).unwrap();
    fs::create_dir(&other).unwrap();
    let path = directory.join("identity.pem");
    let receipt = replace_blocking(
        &path,
        VALID_ONE,
        None,
        &Redirect(&directory, &moved, &other),
    )
    .unwrap();
    assert_eq!(receipt.state, IdentityCommitState::Unknown);
    assert!(
        receipt
            .error
            .unwrap()
            .starts_with("adb_identity_directory_changed")
    );
    assert!(load(&moved.join("identity.pem")).unwrap().is_some());
    assert!(!other.join("identity.pem").exists());
}

// 固定真实 RSA 夹具；兼容指纹由 OpenSSL 公钥与独立 Python ADB 编码计算。
const EXPECTED_FINGERPRINT: &str =
    "98ebc6dc240fc0e531e2ab89d5c3560411849373dd341075c323a94c1e69a46c";
const VALID_ONE: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDEbKl4kuJpiRPH
2+L8AjL5MKjZHnthpxgxZZQPJAw3CuRk8PoUGC5ulR9G0mZDxCi9atdyzPKvlv4x
pK0+yeTO6LPYffiZo6Dmp29F6gOl1yGEnziUJjrB8yyCThi/xJQbE1VIRn+IyMsZ
j0jZDw8CuLSpzL6MDIW/Um+NSTg3FVHv8MWHB73snlqRReDJWYbNDnjf6+2YiQ49
wdXuegErpEC8+Rj+PQI/p/iWLicJlpd010qnOFhGyRPLg6c1zgzdyFoWX48sKfuG
RW1kfT1zY0dlVr2yK3VGIKpMQpUc4BHcRzpUxMGq5fsmeTwdLix7LQMVcZFce3TI
xqc74Cd1AgMBAAECggEAMEPBCrMQ9jysAx55MlI6AzgdLSiLya18yNp8XJIPfFDt
WQ5LbLeaZSq4Qjc90KX5Gr4PjZJliZbRBBLCTRzf36WXV3lwphPqW/LFaUj8t3na
rxNOnDyekHy3sZcOBsT/XX3NJVLJUKuCGFg4XrmQByuqnNSF97S2ApJ3faCBsyrX
mjNaOtT/j4wJJSQRHB3B3nBslRkWSNUgJ2t8XPpDPGYihR+xYOzCq98X7Xjdc3Wk
V5Cu6DVFtLdl5gg06bfkoyTi75FMZLVo/IJKbDT8Kxx59g7b2SnOQuGWs0Csp/JN
oZ3fbNleK6ViPlKC1Gdpi6UOht058o4y0SxgtpdcOwKBgQD6AiomoK/tLwsV5+10
AzugTX4hUZLN/4EYG+CeLIGs9ZJ86MvOjqYV9iDvTzyem7x2jKKGHdRkqmxkOl16
MGpjpzE42cpOYA1ifXJA1XSsy79SL13xxlmvAMx7ku+JM1VHbLrPPs/q7gX6oYdX
qnf/hthN9+wRQeVARnXNMGNK5wKBgQDJIcCaz6+Z6x5+FlM272t0dv2YTgqZ63ef
lFpfoNy4WlMu3kazzOlhS9QPqq+DYnHCRJeTtdP/Bm8qGHK+1L8/Mcf06oSkJYM1
/Qxz35oMyUznYTcLHK9Tl/j+vaiK/ga7Va8Kqnqc959DOHWnUyjsEbkeg8ivUF9a
ndi8DCNrQwKBgAOBekPWZwElcrtY6DyDOxfRXl5rPWrEFXRYF7tAFoVtYCN+RDVe
TLfsHqQccVYsCuWCrVjCHFNZDHIPW3Y2LZe+JXONokedEzL5XVvJYnx10vX9Eg0s
4d8RXMyyz8cVwDFjNe9oCxRZSB4um65ABrS/mFLnkhjf2q4fDtHUxt+rAoGBAMb/
uBrz5Z/6Ox8xY3/0/nIq0NoCTQbhLGgdVhVLiVZ1N9wlW/rFgRsc9WHS1Pi/TCKT
zwz8WBX4/b++lLkusVILJPWzmyz1WI7wIYP79eU0vfwn+VfrN6UTte4FJF7w2yQ6
sIdzCQGJFnBhyjaVVuXK20fPx519ffqgNjJIKDsVAoGAMWW3K8AG1Hin8LILhCwT
2N0jjxzjP4RJ0aeAepag+hdEaAgJHfFvqLh05NyK+32YhygyE8kzg6UXeP6VOWPf
hc/BFXyk3YuPb5WVJqXO4Kieu7tmAfiqt5K46nHZuLJpe8OhBAeBdwLstnRAmv1y
qO45NFs5+tBQIaYwxJMtHR8=
-----END PRIVATE KEY-----
"#;
const VALID_ONE_PKCS1: &str = r#"-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAxGypeJLiaYkTx9vi/AIy+TCo2R57YacYMWWUDyQMNwrkZPD6
FBgubpUfRtJmQ8QovWrXcszyr5b+MaStPsnkzuiz2H34maOg5qdvReoDpdchhJ84
lCY6wfMsgk4Yv8SUGxNVSEZ/iMjLGY9I2Q8PAri0qcy+jAyFv1JvjUk4NxVR7/DF
hwe97J5akUXgyVmGzQ543+vtmIkOPcHV7noBK6RAvPkY/j0CP6f4li4nCZaXdNdK
pzhYRskTy4OnNc4M3chaFl+PLCn7hkVtZH09c2NHZVa9sit1RiCqTEKVHOAR3Ec6
VMTBquX7Jnk8HS4sey0DFXGRXHt0yManO+AndQIDAQABAoIBADBDwQqzEPY8rAMe
eTJSOgM4HS0oi8mtfMjafFySD3xQ7VkOS2y3mmUquEI3PdCl+Rq+D42SZYmW0QQS
wk0c39+ll1d5cKYT6lvyxWlI/Ld52q8TTpw8npB8t7GXDgbE/119zSVSyVCrghhY
OF65kAcrqpzUhfe0tgKSd32ggbMq15ozWjrU/4+MCSUkERwdwd5wbJUZFkjVICdr
fFz6QzxmIoUfsWDswqvfF+143XN1pFeQrug1RbS3ZeYINOm35KMk4u+RTGS1aPyC
Smw0/CscefYO29kpzkLhlrNArKfyTaGd32zZXiulYj5SgtRnaYulDobdOfKOMtEs
YLaXXDsCgYEA+gIqJqCv7S8LFeftdAM7oE1+IVGSzf+BGBvgniyBrPWSfOjLzo6m
FfYg7088npu8doyihh3UZKpsZDpdejBqY6cxONnKTmANYn1yQNV0rMu/Ui9d8cZZ
rwDMe5LviTNVR2y6zz7P6u4F+qGHV6p3/4bYTffsEUHlQEZ1zTBjSucCgYEAySHA
ms+vmesefhZTNu9rdHb9mE4Kmet3n5RaX6DcuFpTLt5Gs8zpYUvUD6qvg2JxwkSX
k7XT/wZvKhhyvtS/PzHH9OqEpCWDNf0Mc9+aDMlM52E3CxyvU5f4/r2oiv4Gu1Wv
Cqp6nPefQzh1p1Mo7BG5HoPIr1BfWp3YvAwja0MCgYADgXpD1mcBJXK7WOg8gzsX
0V5eaz1qxBV0WBe7QBaFbWAjfkQ1Xky37B6kHHFWLArlgq1YwhxTWQxyD1t2Ni2X
viVzjaJHnRMy+V1byWJ8ddL1/RINLOHfEVzMss/HFcAxYzXvaAsUWUgeLpuuQAa0
v5hS55IY39quHw7R1MbfqwKBgQDG/7ga8+Wf+jsfMWN/9P5yKtDaAk0G4SxoHVYV
S4lWdTfcJVv6xYEbHPVh0tT4v0wik88M/FgV+P2/vpS5LrFSCyT1s5ss9ViO8CGD
+/XlNL38J/lX6zelE7XuBSRe8NskOrCHcwkBiRZwYco2lVblyttHz8edfX36oDYy
SCg7FQKBgDFltyvABtR4p/CyC4QsE9jdI48c4z+ESdGngHqWoPoXRGgICR3xb6i4
dOTcivt9mIcoMhPJM4OlF3j+lTlj34XPwRV8pN2Lj2+VlSalzuConru7ZgH4qreS
uOpx2biyaXvDoQQHgXcC7LZ0QJr9cqjuOTRbOfrQUCGmMMSTLR0f
-----END RSA PRIVATE KEY-----
"#;
const VALID_TWO: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCyUtxK9aGg094R
hyX/WNBQ5Z/d7fxSfy5rK6m4UA+ljk5Y0hoJAzBSSYK5YDmkLaw4ighggWOAiiRT
mdN2eU0oWxQfunNUGOw0XOLxSYb3RSlZYyFuQHLW8essCt9jC/enNWOU73PeCLAP
upBfhD7j8A2nuTkyk/albFFBIZYopGh8+LFfcRbJ7+SGzrgNJoxPA/NTV1f0AqWa
NJiPdmCAROwoawhrHXDmLQxr/TfJwMDffvxsg1E9Ijty+3NaMqVvFfX97YKqPGfC
2YWv7ZGO91bXTmkVYUkBWEjttcmPyICcH5r/kGpJC7u9IDDDwK2R5Bih8UC50stV
FaeC0f6TAgMBAAECggEAE2H9TuqHEHem/im+ABTTw89JwrIxCHiJf52l24JcSQcA
Thg8OzmNAYy6+FJUwZszSov6YB8ARUL+stWYDhseP2Iy/EXkbkItPn3QLyDqWis6
1Nv5EMZRlTqDcOyXnmj5GMQtWE10vzAbjwIc2j0CJv17Rn1UEcLSfuWYqWcwrqcN
rUlNI5SEbpjqZI0LsrvYBpqeCFnVdTtceLcn9odv72uLIqcP+mdT81UyYxJwwePw
PNthDmqxKeD7rVR9a8Ira8G8RliPrCVqK4ykwYvUnXZasKMCVZnwpUMdboUl52wA
20ugI/B7j8eDGOIFjBYSYAR7gXdqowa7EoWP7pWylQKBgQDh5lSzhaF+VhZdzFTc
WcvVLNg4vWXAMgFFfSTodTug5qKAcPuivPk0Ikwkhn2aOrbp/P3cFbj+Son+xgWK
jIQfGl/XZLs6XURSKuY/AES76rLcXGUP9IhDDMe/YLH0SglqIkpN0G/5phVzSEGq
ezXJfa3Tj912VqNgP6Ok6EKXlwKBgQDKFal+IjOAQzbEJYkj/yB4MOZmlU042EZr
/PJWrv7zLOgZ87HuOb9P/GKBkrR3r9MDJib/m35iqu4ksbLE8mypu1xmk/3Lko8H
Kn3gKv5Xfav9mRd+KGcXxeP6GhWWwcBxgzaof6hx68Al1amOKvGejgt8Sk3cl38y
HSrEFdtQZQKBgGAG/IyPyrWcvMdEu/IrjdVhycxc3qsT1qyGZTEX3LAqOnvlC2MD
d9/skHeaYDw2p1jSPcvXxBr87qpJ3UMnNmbOXF2AqYJG8WsIZ3XylEVZoIzCDgf5
SA9QmHzHCv6wlk3yo6luaJs0ObwWxCtHUvcDIOhlKJxMegjJJLROMzijAoGAQw6r
HprUwiQLoUzfVB2NtbRsT/ANHubNf3oBJHiPSzxEjJAMJAPvkugp+9slnW2vtKTN
XhZH+w/DVFPPAYF8Q1pT0AodtpacdYFJIcDCg1/FWbKaVBeuFfppqw1KyqriZAhp
c8Jgr+TN7wAWcoGXiciS0RyK978hywxYq5ahHu0CgYEAoSYXi+MzVHovJxXVuLNN
G9gfDRPwAsx9n4rmosIRiz0VXhZCyTdKo1xkzc6SM5TIi918ZxuXhIyzzckbEEi2
gPmnHLpztmG5AH43L6bPEM0SMiU8SAj+P+JM4ntb2DWmQI4nTfAnzJH0qixXixT+
MXyqrPd2j/TpCrsT+37Zia4=
-----END PRIVATE KEY-----
"#;
const INVALID_SIZE: &str = r#"-----BEGIN PRIVATE KEY-----
MIICdwIBADANBgkqhkiG9w0BAQEFAASCAmEwggJdAgEAAoGBAPELrqwb5BBwVNb6
Bqj/JRPXqH0hL3QDRjnmmdOUhkf2+jkAIxo6ynfhsIgTMh+m1Wotwxf9Np1p1Fse
vASDaQ29q+SpfV5abcRdfE/7JXaWNWC/MSfIoRjUyqaUQjg8zVcPzqg878OOAHQx
9bnUGqYBpnAzVtZDLyFEC2oyrY35AgMBAAECgYEAx5ZNvnKlp7rrdMm35AzHraNe
/qUQvrXLWzwG2PtdKI9m5vWnGxvc8+CrJDEIys6AXZegt+dRZovvareLJQ2OWFfn
1iIG/eZA2XJNG6DTNYhFnqUeFB/GNyqQdCDM+4wwxIbMyawZV/nlWIt62XrqUnhh
BRbBgPdIqh7+/mqCoNECQQD8/jfPVQQoGavB8H0zOiceCjBtaDArg5dS1qKJ09Il
ttO4N7dsQQ3G8xm6DD2MIVTtDDTOJJ0RZGbERmMhSmDNAkEA8+kcp6ySk0pRZuZl
jg3Sl7DgTkC7RsW3b3ix2YYCOQPuir7kR/PWKG+ThN/G4HTuDhIt4psVJMhUfzoA
xbPx3QJAaYp0Jd5FmaT77jAxSsmbwABoK3wnfD+tRTWdIPpo1KrssBEuR87rvG91
8BNjKa5OC4XoEYdcrwC/jmn+uMiakQJARw0qFsITtKpaiiIlhTsLlLqmrMT4iQZB
iExdaqM59IfrrikrcLZcNU1DaNqTIYGOczTifvd0MlHVI3avEOh5VQJBAJHi+t/f
j22WWj+rCOYRodPT49KRY5gv2UWnAdFB5lgzDS0K0E9y71wjbNcc/+lqMtdBZv+Y
VKnWyAIqBllfzec=
-----END PRIVATE KEY-----
"#;
const INVALID_EXPONENT: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCxrHIUz95A8im6
3f2NvpWLG6zE+4NAYLA9M4g/zbrpGWEorDqIJQVapAeT+vcBSlXhPiVW3rxEoqlH
+tQTUUuQtt3NX+4CBGxHFYutnHMPigq8NFe5VhEC97l+wNhGgGl4H/OpKR/a5tGk
y8ntUX/1WmfUh1yvEEo5ocLSwanKOUrspsuNPD5PXOIUFkUvlM/ViUKgrqyMbPgB
/gqSybaSZVTLVosHDbkA8FZ+mNxe5GWo9QuvFopDkrfeeoqIU09iFAU5vxHlzeLx
OqQ/BOkdNaHBs75A1LUOnY7H34I09r8+3Q5UxwFajWExqqcGIX2Do++Ggl3vI3Sa
o4cK+RW9AgEDAoIBAHZy9riKlCtMG9HpU7PUY7IScy39AirrICjNBX/efJtmQMXI
JwVuA5HCr7f8pKuG4+t+w48/KC3Bxi/8jWI2MmB56TOVSVatnYS5B8kS91+xXH14
OnuOtgH6e6nV5YRVm6VqonDGFTyZ4RiH2/OLqqORmo2vkx9gMXvBLIyBG9wlFZVA
YGVKw0h3QSA3njtbxibWQXpT56Al4CM2+g9DOJ9sUtG6qp62GZn4NVVueWBgLzDb
tURB/LTEqTja7tQylUsEQpLI5PlRZso5q+nhIpoBQJs48FufIaxxoltxy8Dk261S
B50QtVvPmuvfy2Gp6Zl2hhfF221zMPLVpAu08JMCgYEA1pngOsUoXMZHlS1AaBHn
03GRfy9dzQ8KgNovAnKZHqYXXzKNI6ieuqIUZFIfMIMCkaPq9nmz5ifmcfiCrBrI
spa5vGTFLCK0rSA3Y0omfw09TTC84uEH1LMkGo+Nvypdv0kMc2XKI2e4XJiJVfQR
OmgsZY7Qw/tr/5g14LkmgGsCgYEA0/LmADAjvJxiazaCb8SjUym2YTnTBA0ppvL8
kQlLwv0reV4xZ3Bd1/fnoixT9ctRjTvAhU7/qQyFSBCveC8+vNrT5PjMjk0fG6Gs
vxYMtij2c6ghctZeLdjPAK8nEWlBtnHVj4NjzekdnDdRn/+RZLVFwNQI0M+Kq5Yt
MEBDLHcCgYEAjxFAJy4a6IQvuMjVmraajPZg/3TpM19cVebKAaG7acQPlMxeF8W/
Jxa4QuFqIFdXC8KcpFEimW/u9qWscryFzGR70u3YyBcjHhV6QjFu/14o3iB97JYF
OHdtZwpef3GT1NtdokPcF5p66GWw4/gLfEVy7l811/zyqmV5QHtvAEcCgYEAjUyZ
VXVtKGhBnM8Bn9hs4hvO63viArNxGfdTC1uH11NyUOl2RPWT5U/vwXLio9zhCNKA
WN9VG12uMAsfpXTUfec37fszCYi/Z8Ed1LldzsX5onAWTI7pc+XfVcoaC5uBJEvj
tQJCiUYTvXo2aqpg7c4ugI1bNd+xx7lzdYAsyE8CgYEAhwwAVKDF9Gf9ydIh5mbf
MUslHtjgdHwjyxlaD+UMMPLHv6ftkskHI10uFswol8ZxOButP8LuZaJA9Cgs+S6q
jM9Kc0rOmMTCbRB2GT2/CSaTiHfIAW1rFK27FP5ygdjVJg8gmCXXXqbH80QdV2WP
vgKrzDp1WqEqUBU02CDg+0c=
-----END PRIVATE KEY-----
"#;
