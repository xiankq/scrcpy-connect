//! 私有二进制监督协议只传执行事实；所有长度均在分配前核验。
use std::{
    collections::HashMap,
    io::{self, Read, Write},
};
pub const MAX_FRAME: usize = 4 * 1024 * 1024;
pub const STOP: u8 = 1;
pub struct Launch {
    pub executable: String,
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
    pub ack_fd: Option<i32>,
}
#[derive(Debug)]
pub enum Event {
    Started(u32),
    StartFailed(String),
    TerminationFailed(String),
    Exited(Option<i32>),
}
fn invalid() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "监督协议内容无效")
}
fn number(reader: &mut impl Read) -> io::Result<u32> {
    let mut bytes = [0; 4];
    reader.read_exact(&mut bytes)?;
    Ok(u32::from_be_bytes(bytes))
}
fn text(reader: &mut impl Read) -> io::Result<String> {
    let size = number(reader)? as usize;
    if size > MAX_FRAME {
        return Err(invalid());
    }
    let mut bytes = vec![0; size];
    reader.read_exact(&mut bytes)?;
    String::from_utf8(bytes).map_err(|_| invalid())
}
fn put_text(bytes: &mut Vec<u8>, value: &str) -> io::Result<()> {
    if value.len() > MAX_FRAME {
        return Err(invalid());
    }
    bytes.extend_from_slice(&(value.len() as u32).to_be_bytes());
    bytes.extend_from_slice(value.as_bytes());
    Ok(())
}
fn framed(bytes: Vec<u8>) -> io::Result<Vec<u8>> {
    if bytes.len() > MAX_FRAME {
        return Err(invalid());
    }
    let mut result = (bytes.len() as u32).to_be_bytes().to_vec();
    result.extend_from_slice(&bytes);
    Ok(result)
}
pub fn read_frame(reader: &mut impl Read) -> io::Result<Vec<u8>> {
    let size = number(reader)? as usize;
    if size > MAX_FRAME {
        return Err(invalid());
    }
    let mut bytes = vec![0; size];
    reader.read_exact(&mut bytes)?;
    Ok(bytes)
}
impl Launch {
    pub fn encode(&self) -> io::Result<Vec<u8>> {
        let mut bytes = Vec::new();
        put_text(&mut bytes, &self.executable)?;
        bytes.extend_from_slice(&(self.arguments.len() as u32).to_be_bytes());
        for argument in &self.arguments {
            put_text(&mut bytes, argument)?;
        }
        bytes.extend_from_slice(&(self.environment.len() as u32).to_be_bytes());
        for (key, value) in &self.environment {
            put_text(&mut bytes, key)?;
            put_text(&mut bytes, value)?;
        }
        bytes.extend_from_slice(&self.ack_fd.unwrap_or(-1).to_be_bytes());
        framed(bytes)
    }
    pub fn decode(bytes: &[u8]) -> io::Result<Self> {
        let mut input = bytes;
        let executable = text(&mut input)?;
        let count = number(&mut input)? as usize;
        if count > MAX_FRAME / 4 {
            return Err(invalid());
        }
        let mut arguments = Vec::new();
        for _ in 0..count {
            arguments.push(text(&mut input)?);
        }
        let count = number(&mut input)? as usize;
        if count > MAX_FRAME / 8 {
            return Err(invalid());
        }
        let mut environment = HashMap::new();
        for _ in 0..count {
            environment.insert(text(&mut input)?, text(&mut input)?);
        }
        let ack = number(&mut input)? as i32;
        if !input.is_empty() {
            return Err(invalid());
        }
        Ok(Self {
            executable,
            arguments,
            environment,
            ack_fd: (ack != -1).then_some(ack),
        })
    }
}
impl Event {
    pub fn encode(&self) -> io::Result<Vec<u8>> {
        let mut bytes = Vec::new();
        match self {
            Self::Started(pid) => {
                bytes.push(1);
                bytes.extend_from_slice(&pid.to_be_bytes());
            }
            Self::StartFailed(message) => {
                bytes.push(2);
                put_text(&mut bytes, message)?;
            }
            Self::TerminationFailed(message) => {
                bytes.push(3);
                put_text(&mut bytes, message)?;
            }
            Self::Exited(code) => {
                bytes.push(4);
                bytes.push(u8::from(code.is_some()));
                bytes.extend_from_slice(&code.unwrap_or(0).to_be_bytes());
            }
        }
        framed(bytes)
    }
    pub fn decode(bytes: &[u8]) -> io::Result<Self> {
        let Some((&kind, mut input)) = bytes.split_first() else {
            return Err(invalid());
        };
        let event = match kind {
            1 => Self::Started(number(&mut input)?),
            2 => Self::StartFailed(text(&mut input)?),
            3 => Self::TerminationFailed(text(&mut input)?),
            4 => {
                let mut present = [0];
                input.read_exact(&mut present)?;
                let code = number(&mut input)? as i32;
                match present[0] {
                    0 => Self::Exited(None),
                    1 => Self::Exited(Some(code)),
                    _ => return Err(invalid()),
                }
            }
            _ => return Err(invalid()),
        };
        if !input.is_empty() {
            return Err(invalid());
        }
        Ok(event)
    }
    pub fn write(&self, writer: &mut impl Write) -> io::Result<()> {
        writer.write_all(&self.encode()?)
    }
}
