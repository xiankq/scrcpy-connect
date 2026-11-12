use interop_adb::Identity;

// Fixed test-only key. Public-key encoding comes from Android platform-tools
// `adb pubkey`; the prehashed AUTH signature comes from OpenSSL pkeyutl
// with digest:sha1, so these vectors also check protocol interoperability.
const KEY: &str = include_str!("fixtures/adb_identity.pem");

#[test]
fn android_public_key_encoding_survives_pem_round_trip() {
    let identity = Identity::from_pem(KEY).unwrap();
    let mut expected = include_str!("fixtures/adb_identity.pub")
        .trim()
        .as_bytes()
        .to_vec();
    expected.push(0);
    assert_eq!(identity.public_key("fixture").unwrap(), expected);
    let restored = Identity::from_pem(&identity.to_pkcs8_pem().unwrap()).unwrap();
    assert_eq!(restored.public_key("fixture").unwrap(), expected);
}

#[test]
fn adb_auth_signs_the_prehashed_token_with_sha1_digest_info() {
    let identity = Identity::from_pem(KEY).unwrap();
    let token: Vec<u8> = (0..20).collect();
    let expected = include_bytes!("fixtures/adb_auth_signature.bin");
    assert_eq!(identity.sign_token(&token).unwrap(), expected);
    assert!(identity.sign_token(&token[..19]).is_err());
    assert!(identity.sign_token(&[0; 21]).is_err());
}
