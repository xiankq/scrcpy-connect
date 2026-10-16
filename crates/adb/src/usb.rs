//! USB ADB adapters using nusb's native platform backends (no libusb).
//! Android callers obtain UsbManager permission and keep their UsbDeviceConnection
//! alive before importing its FD; this module never changes the host's debugging settings.
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

/// Runtime capability is separate from USB authorization and attached-device availability.
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
    use crate::{
        OperationOptions,
        error::bounded,
        protocol::{Frame, MAX_PAYLOAD},
    };
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
    use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, DuplexStream, ReadBuf};
    use tokio_util::sync::CancellationToken;

    #[derive(Clone, Debug)]
    pub struct UsbDevice {
        info: DeviceInfo,
    }
    impl UsbDevice {
        pub fn vendor_id(&self) -> u16 {
            self.info.vendor_id()
        }
        pub fn product_id(&self) -> u16 {
            self.info.product_id()
        }
        pub fn serial_number(&self) -> Option<&str> {
            self.info.serial_number()
        }
        /// Open after OS authorization. Windows requires an associated WinUSB driver;
        /// Android should import its authorized UsbDeviceConnection FD instead.
        pub async fn open(&self, options: OperationOptions) -> Result<UsbTransport> {
            bounded(options.timeout, &options.cancellation, async {
                let device = self.info.open().await.map_err(map_error)?;
                open_device(device).await
            })
            .await
        }
    }

    /// Enumerate ADB class/subclass/protocol interfaces without claiming them.
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

    /// Android's UsbManager owns enumeration and the user authorization dialog.
    /// Import its authorized UsbDeviceConnection with `from_authorized_fd`.
    #[cfg(target_os = "android")]
    pub async fn list_devices(_options: OperationOptions) -> Result<Vec<UsbDevice>> {
        Err(UsbError::PlatformAuthorizationRequired.into())
    }

    /// Owns a USB claim and its transfer tasks until dropped. Each ADB header and
    /// payload is a separate USB transfer, terminated with a ZLP when needed.
    pub struct UsbTransport {
        io: DuplexStream,
        cancellation: CancellationToken,
    }
    impl std::fmt::Debug for UsbTransport {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("UsbTransport")
                .field("closed", &self.cancellation.is_cancelled())
                .finish()
        }
    }
    impl AsyncRead for UsbTransport {
        fn poll_read(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            output: &mut ReadBuf<'_>,
        ) -> Poll<io::Result<()>> {
            Pin::new(&mut self.io).poll_read(cx, output)
        }
    }
    impl AsyncWrite for UsbTransport {
        fn poll_write(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            bytes: &[u8],
        ) -> Poll<io::Result<usize>> {
            Pin::new(&mut self.io).poll_write(cx, bytes)
        }
        fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
            Pin::new(&mut self.io).poll_flush(cx)
        }
        fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
            Pin::new(&mut self.io).poll_shutdown(cx)
        }
    }
    impl Drop for UsbTransport {
        fn drop(&mut self) {
            self.cancellation.cancel();
        }
    }

    /// Takes ownership of a duplicated, already-authorized usbfs FD. Do not adopt
    /// Android's Java-owned descriptor with OwnedFd::from_raw_fd: use the borrowed import.
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

    /// Duplicate the caller-owned descriptor. Dropping the ADB connection closes
    /// only the duplicate; Java retains ownership of UsbDeviceConnection's FD.
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
        let mut reader = interface
            .endpoint::<Bulk, In>(input)
            .map_err(map_error)?
            .reader(64 * 1024)
            .with_num_transfers(2);
        let mut writer = interface
            .endpoint::<Bulk, Out>(output)
            .map_err(map_error)?
            .writer(64 * 1024)
            .with_num_transfers(2);
        let (application, bridge) = tokio::io::duplex(128 * 1024);
        let (mut bridge_read, mut bridge_write) = tokio::io::split(bridge);
        let cancellation = CancellationToken::new();
        let read_cancel = cancellation.clone();
        tokio::spawn(async move {
            let operation = async {
                let mut buffer = vec![0; 64 * 1024];
                loop {
                    let count = reader.read(&mut buffer).await?;
                    if count == 0 {
                        return Ok::<(), io::Error>(());
                    }
                    bridge_write.write_all(&buffer[..count]).await?;
                }
            };
            tokio::select! { _ = read_cancel.cancelled() => {}, _ = operation => {} }
            read_cancel.cancel();
        });
        let write_cancel = cancellation.clone();
        tokio::spawn(async move {
            let operation = async {
                loop {
                    let frame = Frame::read(&mut bridge_read, MAX_PAYLOAD, true).await?;
                    let mut serialized = Vec::with_capacity(24 + frame.payload.len());
                    frame.write(&mut serialized).await?;
                    writer.write_all(&serialized[..24]).await?;
                    writer.flush_end_async().await.map_err(Error::Io)?;
                    if !frame.payload.is_empty() {
                        writer.write_all(&serialized[24..]).await?;
                        writer.flush_end_async().await.map_err(Error::Io)?;
                    }
                }
                #[allow(unreachable_code)]
                Ok::<(), Error>(())
            };
            tokio::select! { _ = write_cancel.cancelled() => {}, _ = operation => {} }
            write_cancel.cancel();
        });
        Ok(UsbTransport {
            io: application,
            cancellation,
        })
    }

    fn map_error(error: nusb::Error) -> Error {
        // Keep OS diagnostics while assigning stable application-facing categories.
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

#[cfg(all(test, feature = "usb", any(target_os = "linux", target_os = "android")))]
mod tests {
    use super::*;
    use std::{fs::File, os::fd::AsFd};

    #[tokio::test]
    async fn importing_a_non_usb_fd_is_rejected_without_closing_the_original() {
        let file = File::open("/dev/null").unwrap();
        let result = from_authorized_fd(file.as_fd(), crate::OperationOptions::default()).await;
        assert!(result.is_err());
        assert!(
            file.metadata().is_ok(),
            "the caller-owned FD must remain open"
        );
    }
}
