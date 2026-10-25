fn main() {
    // 每个 FRB 库独立持有回执通道，禁止 ELF 抢占同名运行时函数。
    let target = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if matches!(target.as_str(), "linux" | "android") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-Bsymbolic-functions");
    }
}
