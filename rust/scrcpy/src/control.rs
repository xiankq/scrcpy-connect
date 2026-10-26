//! 类型化控制消息与设备消息；编码不接触产品命令或窗口代次。
use crate::{Error, Result};
use interop_adb::{AdbReader, AdbStream};

pub const CLIPBOARD_MAX: usize = (1 << 18) - 14;
pub const DEVICE_CLIPBOARD_MAX: usize = (1 << 18) - 5;

#[derive(Clone, Copy, Debug)]
pub struct Position {
    pub x: u32,
    pub y: u32,
    pub width: u16,
    pub height: u16,
}
impl Position {
    fn encode(self, bytes: &mut Vec<u8>) -> Result<()> {
        if self.width == 0
            || self.height == 0
            || self.x >= u32::from(self.width)
            || self.y >= u32::from(self.height)
        {
            return Err(Error::new("invalid_argument", "输入位置超出画面。"));
        }
        bytes.extend_from_slice(&self.x.to_be_bytes());
        bytes.extend_from_slice(&self.y.to_be_bytes());
        bytes.extend_from_slice(&self.width.to_be_bytes());
        bytes.extend_from_slice(&self.height.to_be_bytes());
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub enum Message {
    Key {
        action: u8,
        keycode: u32,
        repeat: u32,
        meta_state: u32,
    },
    Text(String),
    Touch {
        action: u8,
        pointer: u64,
        position: Position,
        pressure: f64,
        action_button: u32,
        buttons: u32,
    },
    Scroll {
        position: Position,
        horizontal: f64,
        vertical: f64,
        buttons: u32,
    },
    GetClipboard,
    Clipboard {
        text: String,
        paste: bool,
        sequence: u64,
    },
    /// 固定上游协议使用布尔值，不直接传入 Android SurfaceControl 电源模式常量。
    SetDisplayPower(bool),
    /// 调整已启用 flex_display 的新显示；不更改物理屏幕 wm size 或 density。
    ResizeDisplay {
        width: u16,
        height: u16,
    },
    Rotate,
    ResetVideo,
    StartApp(String),
}

impl Message {
    pub fn encode(&self) -> Result<Vec<u8>> {
        let mut bytes = Vec::new();
        match self {
            Self::Key {
                action,
                keycode,
                repeat,
                meta_state,
            } => {
                if *action > 1 {
                    return Err(Error::new("invalid_argument", "按键动作无效。"));
                }
                bytes.extend_from_slice(&[0, *action]);
                bytes.extend_from_slice(&keycode.to_be_bytes());
                bytes.extend_from_slice(&repeat.to_be_bytes());
                bytes.extend_from_slice(&meta_state.to_be_bytes());
            }
            Self::Text(text) => {
                if text.len() > 300 {
                    return Err(Error::new("invalid_argument", "文本超过协议单条限额。"));
                }
                bytes.push(1);
                bytes.extend_from_slice(&(text.len() as u32).to_be_bytes());
                bytes.extend_from_slice(text.as_bytes());
            }
            Self::Touch {
                action,
                pointer,
                position,
                pressure,
                action_button,
                buttons,
            } => {
                if ![0, 1, 2, 3, 7].contains(action)
                    || !pressure.is_finite()
                    || !(0.0..=1.0).contains(pressure)
                    || *action_button > 31
                    || *buttons > 31
                {
                    return Err(Error::new("invalid_argument", "触控动作、压力或按键无效。"));
                }
                bytes.extend_from_slice(&[2, *action]);
                bytes.extend_from_slice(&pointer.to_be_bytes());
                position.encode(&mut bytes)?;
                bytes.extend_from_slice(
                    &((*pressure * 65536.0) as u32).min(65535).to_be_bytes()[2..],
                );
                bytes.extend_from_slice(&action_button.to_be_bytes());
                bytes.extend_from_slice(&buttons.to_be_bytes());
            }
            Self::Scroll {
                position,
                horizontal,
                vertical,
                buttons,
            } => {
                if !horizontal.is_finite() || !vertical.is_finite() || *buttons > 31 {
                    return Err(Error::new("invalid_argument", "滚动参数无效。"));
                }
                bytes.push(3);
                position.encode(&mut bytes)?;
                for value in [horizontal, vertical] {
                    let fixed = (value.clamp(-16.0, 16.0) * 2048.0).clamp(-32768.0, 32767.0) as i16;
                    bytes.extend_from_slice(&fixed.to_be_bytes());
                }
                bytes.extend_from_slice(&buttons.to_be_bytes());
            }
            Self::GetClipboard => bytes.extend_from_slice(&[8, 0]),
            Self::Clipboard {
                text,
                paste,
                sequence,
            } => {
                if text.len() > CLIPBOARD_MAX {
                    return Err(Error::new("invalid_argument", "剪贴板内容超过协议限额。"));
                }
                bytes.push(9);
                bytes.extend_from_slice(&sequence.to_be_bytes());
                bytes.push(u8::from(*paste));
                bytes.extend_from_slice(&(text.len() as u32).to_be_bytes());
                bytes.extend_from_slice(text.as_bytes());
            }
            Self::SetDisplayPower(on) => bytes.extend_from_slice(&[10, u8::from(*on)]),
            Self::ResizeDisplay { width, height } => {
                if *width == 0 || *height == 0 {
                    return Err(Error::new("invalid_argument", "显示尺寸必须大于零。"));
                }
                bytes.push(21);
                bytes.extend_from_slice(&width.to_be_bytes());
                bytes.extend_from_slice(&height.to_be_bytes());
            }
            Self::Rotate => bytes.push(11),
            Self::ResetVideo => bytes.push(17),
            Self::StartApp(package) => {
                if package.is_empty() || package.len() > 255 || package.contains('\0') {
                    return Err(Error::new("invalid_argument", "应用标识无效。"));
                }
                bytes.extend_from_slice(&[16, package.len() as u8]);
                bytes.extend_from_slice(package.as_bytes());
            }
        }
        Ok(bytes)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DeviceMessage {
    Clipboard(String),
    ClipboardAck(u64),
    Uhid { id: u16, bytes: Vec<u8> },
}

/// 返回完整消息及消费长度；不完整消息保留在调用方有界缓冲中。
pub fn decode_device_message(incoming: &[u8]) -> Result<Option<(DeviceMessage, usize)>> {
    let Some(kind) = incoming.first() else {
        return Ok(None);
    };
    let needed = match kind {
        0 => {
            if incoming.len() < 5 {
                return Ok(None);
            }
            let length = u32::from_be_bytes(incoming[1..5].try_into().expect("固定长度")) as usize;
            if length > DEVICE_CLIPBOARD_MAX {
                return Err(Error::new("control_protocol", "设备剪贴板超过限额。"));
            }
            5 + length
        }
        1 => 9,
        2 => {
            if incoming.len() < 5 {
                return Ok(None);
            }
            5 + u16::from_be_bytes(incoming[3..5].try_into().expect("固定长度")) as usize
        }
        _ => return Err(Error::new("control_protocol", "设备返回未知控制消息。")),
    };
    if incoming.len() < needed {
        return Ok(None);
    }
    let message = match kind {
        0 => DeviceMessage::Clipboard(
            std::str::from_utf8(&incoming[5..needed])
                .map_err(|_| Error::new("control_protocol", "设备剪贴板不是 UTF-8。"))?
                .to_owned(),
        ),
        1 => DeviceMessage::ClipboardAck(u64::from_be_bytes(
            incoming[1..9].try_into().expect("固定序号"),
        )),
        2 => DeviceMessage::Uhid {
            id: u16::from_be_bytes([incoming[1], incoming[2]]),
            bytes: incoming[5..needed].to_vec(),
        },
        _ => unreachable!("上方已校验消息类型"),
    };
    Ok(Some((message, needed)))
}

/// reader 必须由一个循环独占，避免 ACK 与剪贴板正文被两个调用者交错读取。
pub async fn read_device_message(reader: &mut AdbReader) -> Result<DeviceMessage> {
    let mut kind = [0];
    read_exact(reader, &mut kind).await?;
    match kind[0] {
        0 => {
            let mut length = [0; 4];
            read_exact(reader, &mut length).await?;
            let length = u32::from_be_bytes(length) as usize;
            if length > DEVICE_CLIPBOARD_MAX {
                return Err(Error::new("control_protocol", "设备剪贴板超过限额。"));
            }
            let mut bytes = vec![0; length];
            read_exact(reader, &mut bytes).await?;
            Ok(DeviceMessage::Clipboard(String::from_utf8(bytes).map_err(
                |_| Error::new("control_protocol", "设备剪贴板不是 UTF-8。"),
            )?))
        }
        1 => {
            let mut sequence = [0; 8];
            read_exact(reader, &mut sequence).await?;
            Ok(DeviceMessage::ClipboardAck(u64::from_be_bytes(sequence)))
        }
        2 => {
            let mut header = [0; 4];
            read_exact(reader, &mut header).await?;
            let mut bytes = vec![0; u16::from_be_bytes([header[2], header[3]]) as usize];
            read_exact(reader, &mut bytes).await?;
            Ok(DeviceMessage::Uhid {
                id: u16::from_be_bytes([header[0], header[1]]),
                bytes,
            })
        }
        _ => Err(Error::new("control_protocol", "设备返回未知控制消息。")),
    }
}

/// 一次完整写入失败后调用方必须结束该控制通道，不能重放可能已提交的命令。
pub async fn send(stream: &mut AdbStream, message: &Message) -> Result<()> {
    stream.write_all(&message.encode()?).await?;
    Ok(())
}

async fn read_exact(reader: &mut AdbReader, mut bytes: &mut [u8]) -> Result<()> {
    while !bytes.is_empty() {
        let read = reader.read(bytes).await?;
        if read == 0 {
            return Err(interop_adb::Error::Closed.into());
        }
        bytes = &mut bytes[read..];
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Completion {
    Written,
    ClipboardAcknowledged,
}
struct Request {
    message: Message,
    deadline: tokio::time::Instant,
    reply: tokio::sync::oneshot::Sender<Result<Completion>>,
}

/// 独立调用者的有界控制器；应用可在同一编码和设备解码机制外加入自己的持久准入策略。
#[derive(Clone)]
pub struct Channel {
    requests: tokio::sync::mpsc::Sender<Request>,
    events: tokio::sync::broadcast::Sender<DeviceMessage>,
    cancellation: interop_adb::CancellationToken,
    reader_finished: interop_adb::CancellationToken,
    writer_finished: interop_adb::CancellationToken,
}
impl Channel {
    pub fn start(
        mut stream: AdbStream,
        cancellation: interop_adb::CancellationToken,
    ) -> Result<Self> {
        stream.set_write_priority(true)?;
        let (mut reader, mut writer) = stream.into_split();
        let (requests, mut receiver) = tokio::sync::mpsc::channel::<Request>(64);
        let (events, _) = tokio::sync::broadcast::channel(64);
        let pending = std::sync::Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::<
            u64,
            tokio::sync::oneshot::Sender<()>,
        >::new()));
        let reader_finished = interop_adb::CancellationToken::new();
        let writer_finished = interop_adb::CancellationToken::new();
        tokio::spawn({
            let events = events.clone();
            let pending = pending.clone();
            let cancellation = cancellation.clone();
            let finished = reader_finished.clone().drop_guard();
            async move {
                let _finished = finished;
                loop {
                    let message = tokio::select! {
                        _=cancellation.cancelled()=>break,
                        message=read_device_message(&mut reader)=>message,
                    };
                    let Ok(message) = message else {
                        break;
                    };
                    if let DeviceMessage::ClipboardAck(sequence) = &message
                        && let Some(reply) = pending.lock().await.remove(sequence)
                    {
                        let _ = reply.send(());
                    }
                    let _ = events.send(message);
                }
                drop(reader);
                cancellation.cancel();
            }
        });
        tokio::spawn({
            let cancellation = cancellation.clone();
            let finished = writer_finished.clone().drop_guard();
            async move {
                let _finished = finished;
                let mut sequence = 1u64;
                loop {
                    let request = tokio::select! {
                        _=cancellation.cancelled()=>break,
                        request=receiver.recv()=>match request {Some(request)=>request,None=>break},
                    };
                    if request.reply.is_closed() || tokio::time::Instant::now() >= request.deadline
                    {
                        continue;
                    }
                    let mut message = request.message;
                    let mut acknowledgement = None;
                    if let Message::Clipboard {
                        sequence: requested,
                        ..
                    } = &mut message
                    {
                        *requested = sequence;
                        let (send, receive) = tokio::sync::oneshot::channel();
                        pending.lock().await.insert(sequence, send);
                        acknowledgement = Some(receive);
                        sequence = sequence.wrapping_add(1).max(1);
                    }
                    let encoded = match message.encode() {
                        Ok(encoded) => encoded,
                        Err(error) => {
                            let _ = request.reply.send(Err(error));
                            continue;
                        }
                    };
                    let operation = async {
                        writer.write_all(&encoded).await?;
                        if let Some(acknowledgement) = acknowledgement {
                            acknowledgement
                                .await
                                .map_err(|_| interop_adb::Error::Closed)?;
                            Ok(Completion::ClipboardAcknowledged)
                        } else {
                            Ok(Completion::Written)
                        }
                    };
                    let result = tokio::select! {
                        _=cancellation.cancelled()=>Err(interop_adb::Error::Cancelled.into()),
                        result=tokio::time::timeout_at(request.deadline,operation)=>result.unwrap_or_else(|_|Err(Error::new("timeout","控制消息未在期限内完成。"))),
                    };
                    let failed = result.is_err();
                    let _ = request.reply.send(result);
                    // 写入或 ACK 不确定后关闭通道，禁止自动重放可能已提交的动作。
                    if failed {
                        break;
                    }
                }
                drop(writer);
                cancellation.cancel();
                pending.lock().await.clear();
            }
        });
        Ok(Self {
            requests,
            events,
            cancellation,
            reader_finished,
            writer_finished,
        })
    }
    /// 完成信号在读写半流销毁之后发出；调用方可据此建立本机 CLSE 发送栅栏。
    pub async fn close(&self) {
        self.cancellation.cancel();
        self.reader_finished.cancelled().await;
        self.writer_finished.cancelled().await;
    }
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<DeviceMessage> {
        self.events.subscribe()
    }
    pub async fn send(&self, message: Message, timeout: std::time::Duration) -> Result<Completion> {
        message.encode()?;
        let deadline = tokio::time::Instant::now() + timeout;
        let (reply, receive) = tokio::sync::oneshot::channel();
        let operation = async {
            self.requests
                .send(Request {
                    message,
                    deadline,
                    reply,
                })
                .await
                .map_err(|_| interop_adb::Error::Closed)?;
            receive.await.map_err(|_| interop_adb::Error::Closed)?
        };
        tokio::select! {
            _=self.cancellation.cancelled()=>Err(interop_adb::Error::Cancelled.into()),
            result=tokio::time::timeout_at(deadline,operation)=>result.unwrap_or_else(|_|Err(Error::new("timeout","控制队列未在期限内完成。"))),
        }
    }
}

/// 调用方可观察的完成事实；Admitted 仅供上层有界输入队列报告本机准入。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ControlCompletion {
    Admitted,
    Written,
    ClipboardAcknowledged,
}
