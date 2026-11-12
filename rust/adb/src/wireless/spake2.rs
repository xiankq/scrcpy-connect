// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! 实现 BoringSSL 的 SPAKE2，运行于 edwards25519，使用其专有 transcript，与 RFC 9382、CFRG 草案及 crates.io spake2 实现均不兼容。adbd 使用此变体。本实现需保留两项细节：M、N 掩码点由哈希直接取得，未清 cofactor，位于素数阶子群之外；相乘标量必须保留完整 256 位，不能按群阶约减，否则结果改变，因此密码与私有标量都按普通 256 位数处理。密码由配对码拼接 TLS exporter 输出形成；名称保留末尾 NUL，AOSP 的 sizeof("adb pair client") 为 16 字节而非 15。

use std::vec::Vec;

use curve25519_dalek::edwards::{CompressedEdwardsY, EdwardsPoint};
use curve25519_dalek::scalar::Scalar;
use curve25519_dalek::traits::Identity;
use rsa::rand_core::CryptoRngCore;
use sha2::{Digest, Sha512};
use subtle::{Choice, ConditionallySelectable, ConstantTimeEq};
use zeroize::Zeroizing;

/// SHA256("edwards25519 point generation seed (M)") 首次即落在曲线上，因此哈希本身即为该点。
const M_BYTES: [u8; 32] = [
    0x5a, 0xda, 0x7e, 0x4b, 0xf6, 0xdd, 0xd9, 0xad, 0xb6, 0x62, 0x6d, 0x32, 0x13, 0x1c, 0x6b, 0x5c,
    0x51, 0xa1, 0xe3, 0x47, 0xa3, 0x47, 0x8f, 0x53, 0xcf, 0xcf, 0x44, 0x1b, 0x88, 0xee, 0xd1, 0x2e,
];

/// SHA256("edwards25519 point generation seed (N)")，同上。
const N_BYTES: [u8; 32] = [
    0x10, 0xe3, 0xdf, 0x0a, 0xe3, 0x7d, 0x8e, 0x7a, 0x99, 0xb5, 0xfe, 0x74, 0xb4, 0x46, 0x72, 0x10,
    0x3d, 0xbd, 0xdc, 0xbd, 0x06, 0xaf, 0x68, 0x0d, 0x71, 0x32, 0x9a, 0x11, 0x69, 0x3b, 0xc7, 0x78,
];

/// 素数阶子群的阶，以小端表示。
const ORDER: [u8; 32] = [
    0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

/// 交换角色。主控始终为 Alice；算法对称，测试或模拟器替代设备时需要 Bob，因此两者均公开。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Role {
    /// 使用 M 掩码，在 transcript 中排在前面。
    Alice,
    /// 使用 N 掩码，仅设备为 Bob。
    #[cfg(test)]
    Bob,
}

/// 交换无法继续的原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Spake2Error {
    /// 对端消息不是 32 字节。
    MessageLength(usize),
    /// 对端消息为 32 字节，但不能表示曲线点。
    NotAPoint,
}

impl core::fmt::Display for Spake2Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::MessageLength(n) => write!(f, "spake2 message is {n} bytes, not 32"),
            Self::NotAPoint => f.write_str("spake2 message does not decode to a curve point"),
        }
    }
}

impl core::error::Error for Spake2Error {}

/// 两个 256 位小端数相加，丢弃进位，刻意不作模约减。
fn add_assign(a: &mut [u8; 32], b: &[u8; 32]) {
    let mut carry = 0u16;
    for i in 0..32 {
        let sum = u16::from(a[i]) + u16::from(b[i]) + carry;
        a[i] = sum as u8;
        carry = sum >> 8;
    }
}

/// 就地将 256 位小端数乘二。
fn double_assign(a: &mut [u8; 32]) {
    let copy = *a;
    add_assign(a, &copy);
}

/// 将 256 位小端数乘八，对应 BoringSSL left_shift_3。输入是小于 2^253 的已约减标量，因此高位无损失。
fn left_shift_3(n: &mut [u8; 32]) {
    let mut carry = 0u8;
    for byte in n.iter_mut() {
        let next = *byte >> 5;
        *byte = (*byte << 3) | carry;
        carry = next;
    }
}

/// 按完整 256 位数进行常数时间标量乘法。不使用 Scalar，因为其按群阶约减，而掩码点具有 torsion，约减会改变结果。
fn mul_raw(point: &EdwardsPoint, scalar: &[u8; 32]) -> EdwardsPoint {
    let mut acc = EdwardsPoint::identity();
    for byte in scalar.iter().rev() {
        for bit in (0..8).rev() {
            acc = acc + acc;
            let sum = acc + point;
            let take = Choice::from((byte >> bit) & 1);
            acc = EdwardsPoint::conditional_select(&acc, &sum, take);
        }
    }
    acc
}

/// 将 64 字节约减为标量，返回其 32 字节小端表示。
fn reduce_wide(wide: &[u8; 64]) -> [u8; 32] {
    Scalar::from_bytes_mod_order_wide(wide).to_bytes()
}

/// 按 BoringSSL transcript 规则，在 data 前添加 8 字节小端长度。
fn absorb(hash: &mut Sha512, data: &[u8]) {
    hash.update((data.len() as u64).to_le_bytes());
    hash.update(data);
}

/// adbd 使用的 BoringSSL edwards25519 SPAKE2 单方实现，不是 RFC 9382 或 spake2 crate 的方案。pair 以 Alice 角色执行；公开类型供测试或模拟器执行设备角色。持有的标量与共享点字节使用后清零，但两类副本无法清除：sha2 0.10 无清理 SHA-512 工作状态的接口，因此密码与 transcript 哈希状态可能留在已释放内存，transcript 状态等价于最终密钥；另有标量与曲线计算沿途留下的栈临时值。密钥只用于本次双向各一个 PeerInfo。
pub struct Spake2 {
    role: Role,
    my_name: Vec<u8>,
    their_name: Vec<u8>,
    /// 临时标量，为八的倍数且不作模约减。
    private_key: Zeroizing<[u8; 32]>,
    /// 密码完整 SHA-512 值，由 transcript 吸收。
    password_hash: Zeroizing<[u8; 64]>,
    /// cofactor 修正后的密码标量，同样不作模约减。
    password_scalar: Zeroizing<[u8; 32]>,
    my_msg: [u8; 32],
}

impl Spake2 {
    /// 开始交换并生成本方消息。password 必须包含完整配对码和 TLS exporter 输出；名称也完整包含 NUL。adbd 主控 Alice 使用 b"adb pair client\0"，设备 Bob 使用 b"adb pair server\0"，每一方均先传自身名称。
    pub fn new<R: CryptoRngCore>(
        role: Role,
        my_name: &[u8],
        their_name: &[u8],
        password: &[u8],
        rng: &mut R,
    ) -> Self {
        let mut wide = Zeroizing::new([0u8; 64]);
        rng.fill_bytes(wide.as_mut());
        let mut private_key = Zeroizing::new(reduce_wide(&wide));
        // 清除本方标量的 cofactor，使对端掩码中的小阶点在后续相消。
        left_shift_3(&mut private_key);

        let password_hash = Zeroizing::new(Sha512::digest(password).into());
        let password_scalar = Zeroizing::new(Self::password_scalar(&password_hash));

        let mask = match role {
            Role::Alice => Self::point(&M_BYTES),
            #[cfg(test)]
            Role::Bob => Self::point(&N_BYTES),
        };
        // 与掩码点不同，此处约减无害；基点具有素数阶，乘积相同。
        let base = EdwardsPoint::mul_base(&Scalar::from_bytes_mod_order(*private_key));
        let my_msg = (base + mul_raw(&mask, &password_scalar))
            .compress()
            .to_bytes();

        Self {
            role,
            my_name: my_name.into(),
            their_name: their_name.into(),
            private_key,
            password_hash,
            password_scalar,
            my_msg,
        }
    }

    /// 本方 32 字节消息，作为 SPAKE2_MSG 包发送。
    pub fn message(&self) -> &[u8; 32] {
        &self.my_msg
    }

    /// 接收对端消息；密码一致时导出双方相同的 64 字节。此步不能判断密码是否一致，只有首个加密消息认证失败才显现。无论结果如何本交换均被消耗：标量仅用于一个对端，退出时清零秘密。若仍需 message，须提前取得；返回结果在释放时自行清零。
    pub fn finish(self, their_msg: &[u8]) -> Result<Zeroizing<[u8; 64]>, Spake2Error> {
        let their_msg: [u8; 32] = their_msg
            .try_into()
            .map_err(|_| Spake2Error::MessageLength(their_msg.len()))?;

        let masked = CompressedEdwardsY(their_msg)
            .decompress()
            .ok_or(Spake2Error::NotAPoint)?;

        // 与 BoringSSL 一样不检查子群；已清 cofactor 的本方标量会消除 torsion。
        let peer_mask = match self.role {
            Role::Alice => Self::point(&N_BYTES),
            #[cfg(test)]
            Role::Bob => Self::point(&M_BYTES),
        };
        let unmasked = masked - mul_raw(&peer_mask, &self.password_scalar);
        let shared = Zeroizing::new(mul_raw(&unmasked, &self.private_key).compress().to_bytes());

        let (alice_name, bob_name, alice_msg, bob_msg) = match self.role {
            Role::Alice => (&self.my_name, &self.their_name, &self.my_msg, &their_msg),
            #[cfg(test)]
            Role::Bob => (&self.their_name, &self.my_name, &their_msg, &self.my_msg),
        };

        // 无论哪一方构建，始终按 Alice 的顺序排列。
        let mut hash = Sha512::new();
        absorb(&mut hash, alice_name);
        absorb(&mut hash, bob_name);
        absorb(&mut hash, alice_msg);
        absorb(&mut hash, bob_msg);
        absorb(&mut hash, shared.as_ref());
        absorb(&mut hash, self.password_hash.as_ref());
        Ok(Zeroizing::new(hash.finalize().into()))
    }

    /// 采用 BoringSSL cofactor 修正的密码标量。掩码点具有 torsion，标量若不是八的倍数会泄露最多三位密码；BoringSSL 先约减哈希，再依次检查低三位，置位时分别加 l、2l、4l，之后不再约减。
    fn password_scalar(password_hash: &[u8; 64]) -> [u8; 32] {
        let mut scalar = reduce_wide(password_hash);
        let mut order = ORDER;
        for bit in 0..3u32 {
            let mask = 1u8 << bit;
            let set = (scalar[0] & mask).ct_eq(&mask);
            let mut addend = [0u8; 32];
            for (dst, src) in addend.iter_mut().zip(order.iter()) {
                *dst = u8::conditional_select(&0, src, set);
            }
            add_assign(&mut scalar, &addend);
            double_assign(&mut order);
        }
        debug_assert_eq!(scalar[0] & 7, 0);
        scalar
    }

    /// 两个固定掩码点之一。
    fn point(bytes: &[u8; 32]) -> EdwardsPoint {
        CompressedEdwardsY(*bytes)
            .decompress()
            .expect("M and N are curve points, checked by a test")
    }
}
