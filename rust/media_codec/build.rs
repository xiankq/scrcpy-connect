use std::{env, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=MEDIA_CODEC_FFMPEG_ROOT");
    println!("cargo:rerun-if-env-changed=LIBCLANG_PATH");
    println!("cargo:rerun-if-env-changed=MEDIA_CODEC_SYSROOT");
    println!("cargo:rerun-if-env-changed=MEDIA_CODEC_CLANG_RESOURCE_DIR");
    println!("cargo:rerun-if-env-changed=MEDIA_CODEC_CLANG_TARGET");
    println!("cargo:rerun-if-changed=../../packages/media_codec/native/media_codec.h");
    println!("cargo:rerun-if-changed=../../packages/media_codec/third_party/ffmpeg.lock.json");
    println!("cargo:rerun-if-changed=../../packages/media_codec/third_party/patches");
    let prefix = PathBuf::from(
        env::var_os("MEDIA_CODEC_FFMPEG_ROOT")
            .expect("MEDIA_CODEC_FFMPEG_ROOT must point to the pinned decode-only FFmpeg build"),
    );
    assert!(
        prefix.join("media-codec-build.json").is_file(),
        "FFmpeg build receipt missing"
    );
    println!(
        "cargo:rerun-if-changed={}",
        prefix.join("media-codec-build.json").display()
    );
    for archive in [
        "libavcodec.a",
        "libavutil.a",
        "libswscale.a",
        "libdav1d.a",
        "avcodec.lib",
        "avutil.lib",
        "swscale.lib",
        "dav1d.lib",
    ] {
        let path = prefix.join("lib").join(archive);
        if path.exists() {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
    let include = prefix.join("include");
    let target = env::var("TARGET").unwrap();
    let android = target.contains("android");
    let header = format!(
        r#"
#include <errno.h>
#include <libavcodec/avcodec.h>
#include <libavutil/buffer.h>
#include <libavutil/error.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
{}
#include "media_codec.h"
enum {{ MC_EAGAIN = AVERROR(EAGAIN), MC_ENOMEM = AVERROR(ENOMEM),
 MC_EOF = AVERROR_EOF, MC_EXTERNAL = AVERROR_EXTERNAL,
 MC_NO_DECODER = AVERROR_DECODER_NOT_FOUND }};
static const int64_t MC_NO_PTS = AV_NOPTS_VALUE;
"#,
        if android {
            "#include <libavcodec/mediacodec.h>\n#include <libavutil/hwcontext_mediacodec.h>"
        } else {
            ""
        }
    );
    let clang_target = env::var("MEDIA_CODEC_CLANG_TARGET").unwrap_or_else(|_| {
        match target.as_str() {
            "aarch64-apple-ios-sim" => "arm64-apple-ios13.0-simulator",
            "x86_64-apple-ios" => "x86_64-apple-ios13.0-simulator",
            "aarch64-apple-ios" => "arm64-apple-ios13.0",
            "aarch64-apple-darwin" => "arm64-apple-macos10.15",
            "x86_64-apple-darwin" => "x86_64-apple-macos10.15",
            _ => &target,
        }
        .to_owned()
    });
    let mut bindings = bindgen::Builder::default()
        .header_contents("media_codec_bindings.h", &header)
        .clang_arg(format!("-I{}", include.display()))
        .clang_arg(format!(
            "-I{}",
            PathBuf::from("../../packages/media_codec/native")
                .canonicalize()
                .unwrap()
                .display()
        ))
        .clang_arg(format!("--target={clang_target}"))
        .allowlist_type("AV.*|Sws.*|mc_.*")
        .allowlist_function("av.*|sws_.*")
        .allowlist_var("AV.*|SWS_.*|FF_THREAD_SLICE|MC_.*")
        .default_enum_style(bindgen::EnumVariation::Consts)
        .prepend_enum_name(false)
        .derive_debug(false)
        .layout_tests(false)
        .generate_comments(false);
    if let Some(sysroot) = env::var_os("MEDIA_CODEC_SYSROOT") {
        bindings = bindings.clang_arg(format!("--sysroot={}", PathBuf::from(sysroot).display()));
    }
    let resource = env::var_os("MEDIA_CODEC_CLANG_RESOURCE_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            let library = PathBuf::from(env::var_os("LIBCLANG_PATH")?);
            [library.join("clang"), library.join("../lib/clang")]
                .into_iter()
                .find_map(|directory| {
                    std::fs::read_dir(directory)
                        .ok()?
                        .filter_map(Result::ok)
                        .map(|entry| entry.path())
                        .filter(|path| path.join("include/limits.h").exists())
                        .max()
                })
        });
    if let Some(resource) = resource {
        bindings = bindings.clang_arg(format!("-resource-dir={}", resource.display()));
    }
    if target.ends_with("msvc") {
        if let Ok(include) = env::var("INCLUDE") {
            for path in include.split(';').filter(|path| !path.is_empty()) {
                bindings = bindings.clang_arg("-isystem").clang_arg(path);
            }
        }
    }
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    bindings
        .generate()
        .expect("Generate FFmpeg bindings for the selected target")
        .write_to_file(output.join("ffmpeg.rs"))
        .unwrap();
    println!(
        "cargo:rustc-link-search=native={}",
        prefix.join("lib").display()
    );
    for name in ["swscale", "avcodec", "dav1d", "avutil"] {
        if name == "dav1d"
            && !prefix.join("lib/libdav1d.a").exists()
            && !prefix.join("lib/dav1d.lib").exists()
        {
            continue;
        }
        println!("cargo:rustc-link-lib=static={name}");
    }
    if target.contains("apple") {
        // FFmpeg 的 VideoToolbox 使用 __builtin_available；Rust 链接带
        // -nodefaultlibs，必须显式补入 clang 的可用性检查运行库。
        let sdk = if target.contains("darwin") {
            "macosx"
        } else if target.ends_with("-sim") || target.starts_with("x86_64-") {
            "iphonesimulator"
        } else {
            "iphoneos"
        };
        let resource = std::process::Command::new("xcrun")
            .args(["--sdk", sdk, "clang", "--print-resource-dir"])
            .output()
            .expect("Find Apple clang runtime");
        assert!(resource.status.success(), "Find Apple clang runtime failed");
        let directory =
            PathBuf::from(String::from_utf8(resource.stdout).unwrap().trim()).join("lib/darwin");
        let runtime = match sdk {
            "macosx" => "clang_rt.osx",
            "iphonesimulator" => "clang_rt.iossim",
            _ => "clang_rt.ios",
        };
        let source = directory.join(format!("lib{runtime}.a"));
        assert!(source.is_file(), "Missing Apple compiler runtime");
        // Rust 不能把多架构 iOS 归档合入目标静态库；
        // 只在构建输出中裁出目标架构，保留已安装 SDK 的原始文件。
        let runtime_dir = output.join("apple-runtime");
        std::fs::create_dir_all(&runtime_dir).unwrap();
        let arch = if target.starts_with("aarch64-") {
            "arm64"
        } else {
            "x86_64"
        };
        let thin = std::process::Command::new("xcrun")
            .arg("lipo")
            .arg(&source)
            .args(["-thin", arch, "-output"])
            .arg(runtime_dir.join(format!("lib{runtime}.a")))
            .status()
            .expect("Thin Apple compiler runtime");
        assert!(thin.success(), "Thin Apple compiler runtime failed");
        println!("cargo:rerun-if-changed={}", source.display());
        println!("cargo:rustc-link-search=native={}", runtime_dir.display());
        println!("cargo:rustc-link-lib=static={runtime}");
        for framework in [
            "VideoToolbox",
            "CoreMedia",
            "CoreVideo",
            "CoreFoundation",
            "Security",
        ] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
    } else if target.contains("android") {
        for name in ["android", "log", "mediandk", "z", "m", "dl", "atomic"] {
            println!("cargo:rustc-link-lib={name}");
        }
    } else if target.contains("windows") {
        for name in ["bcrypt", "ole32", "uuid", "dxva2", "d3d11"] {
            println!("cargo:rustc-link-lib={name}");
        }
    } else {
        for name in ["va", "va-drm", "drm", "m", "dl", "pthread"] {
            println!("cargo:rustc-link-lib={name}");
        }
        if let Some(paths) = env::var_os("LIBRARY_PATH") {
            for path in env::split_paths(&paths).filter(|path| !path.as_os_str().is_empty()) {
                println!("cargo:rustc-link-search=native={}", path.display());
            }
        }
    }
}
