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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_key_schedule_wipes_itself_on_drop() {
        // AES-GCM zeroize 特性必须在配对会话释放时同时清除轮密钥与认证状态。
        fn wiped_on_drop<T: zeroize::ZeroizeOnDrop>() {}
        wiped_on_drop::<aes::Aes128>();
        wiped_on_drop::<Aes128Gcm>();
    }

    fn pair() -> (Cipher, Cipher) {
        let material = [0x5Au8; 64];
        (Cipher::new(&material), Cipher::new(&material))
    }

    #[test]
    fn the_first_nonce_is_all_zeroes_and_the_next_counts_up() {
        assert_eq!(Cipher::nonce(0), [0u8; 12]);
        assert_eq!(
            Cipher::nonce(1),
            [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "the counter is little-endian in the first eight bytes"
        );
        assert_eq!(
            Cipher::nonce(0x0102_0304_0506_0708),
            [8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0]
        );
    }

    #[test]
    fn the_two_directions_count_apart() {
        // 双方加密使用自身计数器、解密使用对端计数器；无论反方向已处理多少消息，加密与解密必须使用相同编号。
        let (mut host, mut device) = pair();
        let _ = device.seal(b"device spoke first");

        let sealed = host.seal(b"host message");

        assert_eq!(device.open(&sealed).unwrap(), b"host message");
    }

    #[test]
    fn a_different_password_cannot_open_the_message() {
        // 配对码错误仅产生此信号：密钥材料不同导致认证标签失败。
        let mut host = Cipher::new(&[0x5Au8; 64]);
        let mut device = Cipher::new(&[0xA5u8; 64]);

        let sealed = host.seal(b"peer info");

        assert_eq!(device.open(&sealed), None);
    }

    #[test]
    fn the_first_message_is_byte_for_byte_what_another_library_produces() {
        // 固定双方首条消息必须一致的 HKDF info、零 salt 和 12 字节全零 nonce；后续计数器位置由上方测试固定。Node crypto 的 hkdfSync 与 aes-128-gcm（OpenSSL 3.6）对相同输入生成相同字节。
        let mut cipher = Cipher::new(&[0x5Au8; 64]);

        let sealed = cipher.seal(b"adb pairing probe");

        let expected = [
            0x0e, 0xd1, 0x25, 0xb7, 0x0e, 0x3a, 0xf6, 0x4b, 0x27, 0xa9, 0x74, 0xb9, 0xfa, 0xc0,
            0x38, 0xa7, 0x82, 0xbe, 0xdf, 0xcb, 0x57, 0x6d, 0x15, 0x4d, 0x92, 0x59, 0x77, 0x37,
            0x0f, 0x1a, 0x41, 0x8e, 0x54,
        ];
        assert_eq!(sealed, expected);
    }
}
