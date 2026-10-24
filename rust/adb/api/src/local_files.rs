//! 无连接依赖的本机文件能力；平台不具备精确路径及描述符机制时明确拒绝。
#[cfg(any(target_os = "linux", target_os = "android"))]
#[path = "local_files_unix.rs"]
mod implementation;
#[cfg(any(target_os = "linux", target_os = "android"))]
pub(super) use implementation::*;

#[cfg(not(any(target_os = "linux", target_os = "android")))]
mod implementation {
    use super::super::*;
    fn unsupported<T>() -> Result<T, LocalFileError> {
        Err(LocalFileError {
            code: LocalFileErrorCode::Unsupported,
            message: "此宿主尚未提供精确本机文件能力。".into(),
            bytes_copied: 0,
            partial_destination_possible: false,
        })
    }
    pub async fn open(_: Vec<Vec<u8>>, _: String, _: u32) -> Result<String, LocalFileError> {
        unsupported()
    }
    pub async fn close_scope(_: String, _: u32) -> Result<(), LocalFileError> {
        unsupported()
    }
    pub async fn stat(_: String, _: Vec<u8>) -> Result<LocalFileStat, LocalFileError> {
        unsupported()
    }
    pub async fn list(_: String, _: Vec<u8>, _: u32) -> Result<LocalFileList, LocalFileError> {
        unsupported()
    }
    pub async fn mkdir(_: String, _: Vec<u8>, _: bool) -> Result<(), LocalFileError> {
        unsupported()
    }
    pub async fn remove(_: String, _: Vec<u8>, _: LocalFileIdentity) -> Result<(), LocalFileError> {
        unsupported()
    }
    pub async fn create_copy(_: String, _: LocalFileCopyRequest) -> Result<String, LocalFileError> {
        unsupported()
    }
    pub async fn run_copy(_: String) -> Result<LocalFileCopyResult, LocalFileError> {
        unsupported()
    }
    pub fn cancel_copy(_: String) -> Result<(), LocalFileError> {
        unsupported()
    }
    pub async fn close_copy(_: String, _: u32) -> Result<(), LocalFileError> {
        unsupported()
    }
    pub async fn commit(
        _: String,
        _: String,
        _: Vec<u8>,
        _: LocalFileIdentity,
    ) -> Result<LocalFileIdentity, LocalFileError> {
        unsupported()
    }
}
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub(super) use implementation::*;
