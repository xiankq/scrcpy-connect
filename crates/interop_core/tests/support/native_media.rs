//! Test observer for the production packet ABI. Reconstructs scrcpy framing in
//! memory so existing independent decoders can inspect the exact delivered data.
#![allow(dead_code)]
use interop_core::media::native::{MediaSinkV1, interop_media_attach, interop_media_detach};
use std::{
    ffi::c_void,
    pin::Pin,
    sync::Mutex,
    task::{Context, Poll},
};
use tokio::io::{AsyncRead, AsyncWriteExt, ReadBuf};

struct Observer {
    sender: Mutex<Option<tokio::sync::mpsc::Sender<Vec<u8>>>>,
}
unsafe extern "C" fn observe(
    context: *mut c_void,
    event: u32,
    _generation: u64,
    codec: u32,
    width: u32,
    height: u32,
    data: *const u8,
    len: usize,
    pts: i64,
    flags: u32,
) -> i32 {
    let observer = unsafe { &*(context as *const Observer) };
    let mut sender = observer.sender.lock().unwrap();
    if event == 3 {
        sender.take();
        return 0;
    }
    let mut bytes = Vec::new();
    if event == 1 && codec != 100 {
        bytes.extend_from_slice(&0x8000_0000u32.to_be_bytes());
        bytes.extend_from_slice(&width.to_be_bytes());
        bytes.extend_from_slice(&height.to_be_bytes());
    }
    if event == 2 || len > 0 {
        let bits = if event == 1 {
            1u64 << 62
        } else {
            pts as u64
                | if flags & 1 != 0 && codec != 100 {
                    1u64 << 61
                } else {
                    0
                }
        };
        bytes.extend_from_slice(&bits.to_be_bytes());
        bytes.extend_from_slice(&(len as u32).to_be_bytes());
        if len > 0 {
            bytes.extend_from_slice(unsafe { std::slice::from_raw_parts(data, len) });
        }
    }
    let Some(sender) = sender.as_ref() else {
        return -1;
    };
    match sender.try_send(bytes) {
        Ok(()) => 0,
        Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => 1,
        Err(_) => -1,
    }
}
pub struct Reader {
    stream: tokio::io::DuplexStream,
    id: String,
    generation: u64,
    _observer: Box<Observer>,
}
impl Reader {
    pub fn attach(id: &str, generation: u64) -> Self {
        let (sender, mut receiver) = tokio::sync::mpsc::channel::<Vec<u8>>(32);
        let (stream, mut output) = tokio::io::duplex(256 * 1024);
        tokio::spawn(async move {
            while let Some(bytes) = receiver.recv().await {
                if output.write_all(&bytes).await.is_err() {
                    break;
                }
            }
        });
        let mut observer = Box::new(Observer {
            sender: Mutex::new(Some(sender)),
        });
        let sink = MediaSinkV1 {
            abi_version: 1,
            struct_size: std::mem::size_of::<MediaSinkV1>() as u32,
            context: (&mut *observer as *mut Observer).cast(),
            event: Some(observe),
        };
        assert_eq!(
            unsafe { interop_media_attach(id.as_ptr(), id.len(), generation, &sink) },
            0
        );
        Self {
            stream,
            id: id.to_owned(),
            generation,
            _observer: observer,
        }
    }
    pub fn video(session: &serde_json::Value) -> Self {
        Self::attach(
            session["videoSourceId"].as_str().unwrap(),
            session["generation"].as_u64().unwrap_or(1),
        )
    }
    pub fn audio(source: &serde_json::Value) -> Self {
        Self::attach(source["audioSourceId"].as_str().unwrap(), 1)
    }
}
impl AsyncRead for Reader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_read(context, buffer)
    }
}
impl Drop for Reader {
    fn drop(&mut self) {
        unsafe {
            interop_media_detach(self.id.as_ptr(), self.id.len(), self.generation);
        }
    }
}
