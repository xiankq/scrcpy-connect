// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! 保护 PeerInfo 交换的密码：AES-128-GCM，密钥由 SPAKE2 共享秘密扩展，nonce 为计数器。AOSP 实现位于 pairing_auth/aes_128_gcm.cpp。

use std::vec::Vec;

use aes_gcm::Aes128Gcm;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::Zeroizing;

/// HKDF info 字符串不带末尾 NUL，与 AOSP 的 sizeof(info) - 1 一致。
const HKDF_INFO: &[u8] = b"adb pairing_auth aes-128-gcm key";

/// AES-128 密钥长度为 16 字节。
const KEY_LEN: usize = 16;

/// GCM 为每条消息增加的字节数。
pub(crate) const TAG_LEN: usize = 16;

/// 一次配对会话的密码。每个方向分别从零计数 nonce，与对端一致；启用 aes-gcm/zeroize 后，释放时清除 AES 密钥调度和 GHASH 状态。
pub(crate) struct Cipher {
    key: Aes128Gcm,
    encrypt_counter: u64,
    decrypt_counter: u64,
}

impl Cipher {
    /// 将 SPAKE2 协商出的 64 字节扩展为会话密钥，与 AOSP 一样不加 salt。
    pub(crate) fn new(key_material: &[u8]) -> Self {
        let hkdf = Hkdf::<Sha256>::new(None, key_material);
        let mut key = Zeroizing::new([0u8; KEY_LEN]);
        hkdf.expand(HKDF_INFO, key.as_mut())
            .expect("HKDF-SHA256 stretches to 8160 bytes, and the key is 16");
        Self {
            // 按引用传递，into() 会留下未清除的副本。
            key: Aes128Gcm::new_from_slice(key.as_ref()).expect("AES-128 uses a 16-byte key"),
            encrypt_counter: 0,
            decrypt_counter: 0,
        }
    }

    /// 第 counter 条消息的 nonce：计数器以小端写入 12 字节中的前 8 字节。
    fn nonce(counter: u64) -> [u8; 12] {
        let mut nonce = [0u8; 12];
        nonce[..8].copy_from_slice(&counter.to_le_bytes());
        nonce
    }

    /// 加密一条消息并消耗一个 nonce。
    pub(crate) fn seal(&mut self, plaintext: &[u8]) -> Vec<u8> {
        let nonce = Self::nonce(self.encrypt_counter);
        let sealed = self
            .key
            .encrypt(
                (&nonce).into(),
                Payload {
                    msg: plaintext,
                    aad: &[],
                },
            )
            .expect("GCM seals anything short of 64 GiB");
        self.encrypt_counter += 1;
        sealed
    }

    /// 解密一条消息，认证失败返回 None；仅成功解密才消耗 nonce。配对中认证失败说明配对码不一致，双方密钥不同。
    pub(crate) fn open(&mut self, ciphertext: &[u8]) -> Option<Vec<u8>> {
        let nonce = Self::nonce(self.decrypt_counter);
        let opened = self
            .key
            .decrypt(
                (&nonce).into(),
                Payload {
                    msg: ciphertext,
                    aad: &[],
                },
            )
            .ok()?;
        self.decrypt_counter += 1;
        Some(opened)
    }
}
