//! 基于 nusb 原生平台后端的 USB ADB adapter，不依赖 libusb。Android 调用方导入 FD 前须取得 UsbManager 权限并保持 UsbDeviceConnection 存活；本模块不更改宿主调试设置。
#[derive(Debug, thiserror::Error)]
pub enum UsbError {
    #[error("USB backend is unavailable on this platform or disabled at build time")]
    Unavailable,
    #[error(
        "Android USB devices must be authorized through UsbManager and imported by file descriptor"
    )]
    PlatformAuthorizationRequired,
    #[error("USB permission denied: {0}")]
    PermissionDenied(String),
    #[error("USB device disconnected: {0}")]
    Disconnected(String),
    #[error("USB interface is busy: {0}")]
    Busy(String),
    #[error("invalid ADB USB interface: {0}")]
    InvalidDescriptor(&'static str),
    #[error("USB operation failed: {0}")]
    Backend(String),
}

/// 运行能力、USB 授权与已连接设备是否可用是不同条件。
pub const fn supported() -> bool {
    cfg!(all(
        feature = "usb",
        any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        )
    ))
}

#[cfg(all(
    feature = "usb",
    any(
        target_os = "linux",
        target_os = "android",
        target_os = "windows",
        target_os = "macos"
    )
))]
mod backend {
    use super::*;
    use crate::{Error, Result};
    use crate::{OperationOptions, error::bounded};
    use nusb::{
        Device, DeviceInfo,
        descriptors::TransferType,
        transfer::{Bulk, In, Out},
    };
    use std::{
        io,
        pin::Pin,
        task::{Context, Poll},
    };
    use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

    #[derive(Clone, Debug)]
    pub struct UsbDevice {
        info: DeviceInfo,
    }
    impl UsbDevice {
        /// 本次附着的不透明身份，独立于可选序列号。
        pub fn id(&self) -> String {
            format!("{:?}", self.info.id())
        }

        pub fn vendor_id(&self) -> u16 {
            self.info.vendor_id()
        }
        pub fn product_id(&self) -> u16 {
            self.info.product_id()
        }
        pub fn product_name(&self) -> Option<&str> {
            self.info.product_string()
        }
        pub fn serial_number(&self) -> Option<&str> {
            self.info.serial_number()
        }
        /// 系统授权后打开。Windows 要求关联 WinUSB 驱动；Android 应导入已授权 UsbDeviceConnection 的 FD。
        pub async fn open(&self, options: OperationOptions) -> Result<UsbTransport> {
            bounded(options.timeout, &options.cancellation, async {
                let device = self.info.open().await.map_err(map_error)?;
                open_device(device).await
            })
            .await
        }
    }

    /// 枚举 ADB class/subclass/protocol 接口，不占用接口。
    #[cfg(not(target_os = "android"))]
    pub async fn list_devices(options: OperationOptions) -> Result<Vec<UsbDevice>> {
        bounded(options.timeout, &options.cancellation, async {
            let devices = nusb::list_devices().await.map_err(map_error)?;
            Ok(devices
                .filter(|device| {
                    device.interfaces().any(|interface| {
                        interface.class() == 0xff
                            && interface.subclass() == 0x42
                            && interface.protocol() == 1
                    })
                })
                .map(|info| UsbDevice { info })
                .collect())
        })
        .await
    }

    /// Android UsbManager 拥有枚举和用户授权对话框；通过 from_authorized_fd 导入已授权 UsbDeviceConnection。
    #[cfg(target_os = "android")]
    pub async fn list_devices(_options: OperationOptions) -> Result<Vec<UsbDevice>> {
        Err(UsbError::PlatformAuthorizationRequired.into())
    }

    /// 直接拥有原生端点缓冲。头部与 payload 分别完成 USB transfer，包括所需短包或 ZLP；没有字节流中转、临时 payload Vec 或 adapter 任务。
    pub struct UsbTransport {
        reader: nusb::io::EndpointRead<Bulk>,
        writer: nusb::io::EndpointWrite<Bulk>,
        boundary: WriteBoundary,
        flushing: bool,
        failed: bool,
    }

    #[derive(Default)]
    struct WriteBoundary {
        header: [u8; 24],
        header_len: usize,
        payload_remaining: usize,
    }
    impl WriteBoundary {
        fn limit(&self) -> usize {
            if self.payload_remaining != 0 {
                self.payload_remaining
            } else {
                24 - self.header_len
            }
        }
        fn accept(&mut self, bytes: &[u8]) -> io::Result<bool> {
            if self.payload_remaining != 0 {
                self.payload_remaining -= bytes.len();
                return Ok(self.payload_remaining == 0);
            }
            self.header[self.header_len..self.header_len + bytes.len()].copy_from_slice(bytes);
            self.header_len += bytes.len();
            if self.header_len != 24 {
                return Ok(false);
            }
            let words =
                crate::protocol::validate_header(&self.header, crate::protocol::MAX_PAYLOAD)
                    .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
            self.payload_remaining = words[3] as usize;
            self.header_len = 0;
            Ok(true)
        }
        fn complete(&self) -> bool {
            self.header_len == 0 && self.payload_remaining == 0
        }
    }
    impl std::fmt::Debug for UsbTransport {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("UsbTransport")
                .field("closed", &self.failed)
                .finish()
        }
    }
    impl AsyncRead for UsbTransport {
        fn poll_read(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            output: &mut ReadBuf<'_>,
        ) -> Poll<io::Result<()>> {
            if self.failed {
                return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
            }
            let result = Pin::new(&mut self.reader).poll_read(cx, output);
            if matches!(result, Poll::Ready(Err(_))) {
                self.failed = true;
            }
            result
        }
    }
    impl AsyncWrite for UsbTransport {
        fn poll_write(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            bytes: &[u8],
        ) -> Poll<io::Result<usize>> {
            if self.failed {
                return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
            }
            if bytes.is_empty() {
                return Poll::Ready(Ok(0));
            }
            if self.flushing {
                match Pin::new(&mut self.writer).poll_flush(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Err(error)) => {
                        self.failed = true;
                        return Poll::Ready(Err(error));
                    }
                    Poll::Ready(Ok(())) => self.flushing = false,
                }
            }
            let length = bytes.len().min(self.boundary.limit());
            let count = match Pin::new(&mut self.writer).poll_write(cx, &bytes[..length]) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(error)) => {
                    self.failed = true;
                    return Poll::Ready(Err(error));
                }
                Poll::Ready(Ok(count)) => count,
            };
            match self.boundary.accept(&bytes[..count]) {
                Err(error) => {
                    self.failed = true;
                    return Poll::Ready(Err(error));
                }
                Ok(true) => {
                    self.writer.submit_end();
                    self.flushing = true;
                }
                Ok(false) => {}
            }
            Poll::Ready(Ok(count))
        }
        fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
            if self.failed {
                return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
            }
            if !self.boundary.complete() {
                self.failed = true;
                return Poll::Ready(Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "partial USB ADB frame",
                )));
            }
            let result = Pin::new(&mut self.writer).poll_flush(cx);
            if matches!(result, Poll::Ready(Err(_))) {
                self.failed = true;
            }
            if matches!(result, Poll::Ready(Ok(()))) {
                self.flushing = false;
            }
            result
        }
        fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
            self.poll_flush(cx)
        }
    }

    /// 接管已复制且已授权的 usbfs FD；不可用 OwnedFd::from_raw_fd 接管 Java 拥有的原描述符，应使用借用导入。
    #[cfg(any(target_os = "linux", target_os = "android"))]
    pub async fn from_owned_fd(
        fd: std::os::fd::OwnedFd,
        options: OperationOptions,
    ) -> Result<UsbTransport> {
        bounded(options.timeout, &options.cancellation, async {
            let device = Device::from_fd(fd).await.map_err(map_error)?;
            open_device(device).await
        })
        .await
    }

    /// 复制调用方拥有的描述符。ADB 连接释放时只关闭副本，Java 继续拥有 UsbDeviceConnection 的 FD。
    #[cfg(any(target_os = "linux", target_os = "android"))]
    pub async fn from_authorized_fd(
        fd: std::os::fd::BorrowedFd<'_>,
        options: OperationOptions,
    ) -> Result<UsbTransport> {
        let duplicate = fd.try_clone_to_owned().map_err(Error::Io)?;
        from_owned_fd(duplicate, options).await
    }

    async fn open_device(device: Device) -> Result<UsbTransport> {
        let selection = device
            .active_configuration()
            .map_err(|_| UsbError::InvalidDescriptor("device has no active configuration"))?
            .interface_alt_settings()
            .find_map(|descriptor| {
                if descriptor.class() != 0xff
                    || descriptor.subclass() != 0x42
                    || descriptor.protocol() != 1
                {
                    return None;
                }
                let mut input = None;
                let mut output = None;
                for endpoint in descriptor
                    .endpoints()
                    .filter(|ep| ep.transfer_type() == TransferType::Bulk)
                {
                    if endpoint.max_packet_size() == 0 {
                        return None;
                    }
                    if endpoint.address() & 0x80 != 0 {
                        if input.replace(endpoint.address()).is_some() {
                            return None;
                        }
                    } else if output.replace(endpoint.address()).is_some() {
                        return None;
                    }
                }
                Some((
                    descriptor.interface_number(),
                    descriptor.alternate_setting(),
                    input?,
                    output?,
                ))
            })
            .ok_or(UsbError::InvalidDescriptor(
                "no unique bulk IN/OUT ADB interface",
            ))?;
        let (number, alternate, input, output) = selection;
        let interface = device.claim_interface(number).await.map_err(map_error)?;
        if interface.get_alt_setting() != alternate {
            interface
                .set_alt_setting(alternate)
                .await
                .map_err(map_error)?;
        }
        let reader = interface
            .endpoint::<Bulk, In>(input)
            .map_err(map_error)?
            .reader(64 * 1024)
            .with_num_transfers(2);
        let writer = interface
            .endpoint::<Bulk, Out>(output)
            .map_err(map_error)?
            .writer(64 * 1024)
            .with_num_transfers(2);
        Ok(UsbTransport {
            reader,
            writer,
            boundary: WriteBoundary::default(),
            flushing: false,
            failed: false,
        })
    }

    fn map_error(error: nusb::Error) -> Error {
        // 保留系统诊断，同时映射为稳定的应用错误分类。
        let message = error.to_string();
        let error = match error.kind() {
            nusb::ErrorKind::PermissionDenied => UsbError::PermissionDenied(message),
            nusb::ErrorKind::Disconnected => UsbError::Disconnected(message),
            nusb::ErrorKind::Busy => UsbError::Busy(message),
            _ => UsbError::Backend(message),
        };
        error.into()
    }
}
#[cfg(all(
    feature = "usb",
    any(
        target_os = "linux",
        target_os = "android",
        target_os = "windows",
        target_os = "macos"
    )
))]
pub use backend::*;
