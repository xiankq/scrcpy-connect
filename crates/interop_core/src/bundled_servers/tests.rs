use super::*;

// The controlled build inputs are an independent oracle. These raw bytes are
// present only in the test executable, never in the shipped Rust library.
pub(crate) fn original(id: &str) -> &'static [u8] {
    match id {
        "scrcpy" => include_bytes!("../../../../servers/vendor/scrcpy-server-v5.0.1"),
        "companion" => include_bytes!("../../../../servers/companion/companion.jar"),
        "arm64-v8a" => {
            include_bytes!("../../../../servers/helpers/bin/arm64-v8a/interop-rename")
        }
        "armeabi-v7a" => {
            include_bytes!("../../../../servers/helpers/bin/armeabi-v7a/interop-rename")
        }
        "x86_64" => include_bytes!("../../../../servers/helpers/bin/x86_64/interop-rename"),
        "x86" => include_bytes!("../../../../servers/helpers/bin/x86/interop-rename"),
        _ => panic!("unknown controlled artifact"),
    }
}

fn write_originals(directory: &Path) {
    for id in IDS {
        std::fs::write(directory.join(id), original(id)).unwrap();
    }
}

#[test]
#[cfg(not(target_os = "android"))]
fn compressed_fallback_restores_all_six_controlled_artifacts() {
    for entry in manifest().unwrap().artifacts {
        assert_eq!(
            decode(&entry, embedded(&entry.id)).unwrap().as_ref(),
            original(&entry.id)
        );
        assert_eq!(get(&entry.id).unwrap(), original(&entry.id));
    }
}

#[test]
fn unpacked_android_directory_restores_the_same_six_controlled_artifacts() {
    let directory = tempfile::tempdir().unwrap();
    write_originals(directory.path());
    let artifacts = from_directory(directory.path()).unwrap();
    assert_eq!(artifacts.0.len(), IDS.len());
    for (id, bytes) in artifacts.0 {
        assert_eq!(bytes.as_ref(), original(&id));
    }
}

#[test]
fn directory_failures_do_not_publish_partial_cache_and_can_be_retried() {
    let directory = tempfile::tempdir().unwrap();
    let cache = OnceLock::new();
    for id in IDS {
        let code = if IDS[2..].contains(&id) {
            "helper_integrity"
        } else {
            "server_integrity"
        };
        write_originals(directory.path());
        let path = directory.path().join(id);
        std::fs::remove_file(&path).unwrap();
        assert_eq!(
            prepare_with(&cache, || from_directory(directory.path()))
                .unwrap_err()
                .code,
            code
        );
        assert!(cache.get().is_none());

        let bytes = original(id);
        std::fs::write(&path, &bytes[..bytes.len() - 1]).unwrap();
        assert_eq!(
            prepare_with(&cache, || from_directory(directory.path()))
                .unwrap_err()
                .code,
            code
        );
        assert!(cache.get().is_none());

        let mut corrupt = bytes.to_vec();
        corrupt[0] ^= 1;
        std::fs::write(&path, corrupt).unwrap();
        assert_eq!(
            prepare_with(&cache, || from_directory(directory.path()))
                .unwrap_err()
                .code,
            code
        );
        assert!(cache.get().is_none());

        let mut oversized = bytes.to_vec();
        oversized.push(0);
        std::fs::write(&path, oversized).unwrap();
        assert_eq!(
            prepare_with(&cache, || from_directory(directory.path()))
                .unwrap_err()
                .code,
            code
        );
        assert!(cache.get().is_none());
    }
    write_originals(directory.path());
    prepare_with(&cache, || from_directory(directory.path())).unwrap();
    for (id, bytes) in &cache.get().unwrap().0 {
        assert_eq!(bytes.as_ref(), original(id));
    }
    // Once loaded, deployments use the immutable verified data; deleting or
    // replacing startup files cannot change a running process's upload bytes.
    std::fs::remove_dir_all(directory.path()).unwrap();
    prepare_with(&cache, || from_directory(directory.path())).unwrap();
    for (id, bytes) in &cache.get().unwrap().0 {
        assert_eq!(bytes.as_ref(), original(id));
    }
}

#[test]
#[cfg(not(target_os = "android"))]
fn compressed_corruption_truncation_and_wrong_metadata_fail_closed() {
    for mut entry in manifest().unwrap().artifacts {
        let compressed = embedded(&entry.id);
        for broken in [
            b"not a zlib stream".as_slice(),
            &compressed[..compressed.len() - 1],
            &compressed[..compressed.len() / 2],
        ] {
            assert!(
                decode(&entry, broken).is_err(),
                "{} accepted broken compression",
                entry.id
            );
        }
        let mut trailing = compressed.to_vec();
        trailing.push(0);
        assert!(decode(&entry, &trailing).is_err());

        entry.size -= 1;
        assert!(decode(&entry, compressed).is_err());
        entry.size += 2;
        assert!(decode(&entry, compressed).is_err());
        entry.size -= 1;
        entry.sha256 = "0".repeat(64);
        assert!(decode(&entry, compressed).is_err());
    }
}
