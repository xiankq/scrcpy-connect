//! 用目标工具链构建 std-only 监督器；不执行目标产物，也不引入运行时资产路径。
use std::{env, path::PathBuf, process::Command};
fn main() {
    println!("cargo:rerun-if-changed=supervisor/main.rs");
    println!("cargo:rerun-if-changed=supervisor/protocol.rs");
    let target = env::var("TARGET").expect("Cargo TARGET");
    let os = env::var("CARGO_CFG_TARGET_OS").expect("Cargo target OS");
    if os != "linux" && os != "android" {
        return;
    }
    let linker_key = format!(
        "CARGO_TARGET_{}_LINKER",
        target.replace('-', "_").to_uppercase()
    );
    println!("cargo:rerun-if-env-changed={linker_key}");
    println!("cargo:rerun-if-env-changed=RUSTC_LINKER");
    println!("cargo:rerun-if-env-changed=CARGO_ENCODED_RUSTFLAGS");
    let linker = env::var("RUSTC_LINKER")
        .ok()
        .or_else(|| env::var(&linker_key).ok());
    if env::var("HOST").expect("Cargo HOST") != target && linker.is_none() {
        panic!("交叉编译监督器必须明确提供目标 linker：{linker_key}");
    }
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR"))
        .join("interop-adb-supervisor");
    let mut command = Command::new(env::var_os("RUSTC").expect("Cargo RUSTC"));
    let encoded = env::var("CARGO_ENCODED_RUSTFLAGS").unwrap_or_default();
    let flags = encoded
        .split('\u{1f}')
        .filter(|flag| !flag.is_empty())
        .collect::<Vec<_>>();
    // ABI、页大小等目标参数与主库保持一致；Cargo TARGET 仍是唯一目标来源。
    assert!(
        !flags
            .iter()
            .any(|flag| *flag == "--target" || flag.starts_with("--target=")),
        "监督器目标只能由 Cargo TARGET 指定"
    );
    command.args(flags);
    command.args([
        "--edition=2024",
        "--target",
        &target,
        "-C",
        "opt-level=s",
        "-C",
        "panic=abort",
        "-C",
        "strip=symbols",
    ]);
    if let Some(linker) = linker {
        command.arg("-C").arg(format!("linker={linker}"));
    }
    let status = command
        .arg("supervisor/main.rs")
        .arg("-o")
        .arg(output)
        .status()
        .expect("启动目标 rustc");
    assert!(status.success(), "目标监督器编译失败");
}
