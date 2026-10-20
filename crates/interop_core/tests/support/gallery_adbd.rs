//! Gallery's adbd boundary: v2 SYNC, legacy framing and verified helper launch.
//! The helper's filesystem syscalls have their own host tests; this fixture
//! models filesystem state while retaining the real upload/read-back protocol.
use super::{DeviceFiles, Node};
use interop_adb::protocol::{self, Frame};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{Arc, Mutex},
};
use tokio::net::TcpStream;

enum Service {
    Plain,
    Sync(Sync),
    Helper(Helper),
    Deployment { directory: String, created: bool },
}
struct Stream {
    service: Service,
    outgoing: VecDeque<Vec<u8>>,
    awaiting_ack: bool,
    close: bool,
}
impl Stream {
    fn new(service: Service) -> Self {
        Self {
            service,
            outgoing: VecDeque::new(),
            awaiting_ack: false,
            close: false,
        }
    }
    fn queue(&mut self, bytes: &[u8], close: bool) {
        self.outgoing.extend(bytes.chunks(4096).map(<[u8]>::to_vec));
        self.close |= close;
    }
}

pub(super) async fn serve(
    mut socket: TcpStream,
    files: Arc<Mutex<DeviceFiles>>,
) -> interop_adb::Result<()> {
    socket.set_nodelay(true)?;
    let connect = Frame::read(&mut socket, protocol::MAX_PAYLOAD, false).await?;
    assert_eq!(connect.command, protocol::CNXN);
    // The legacy fixture reports no v2 features. The modern fixture advertises
    // only protocols actually encoded below: LST2/STA2, LIS2/DNT2 and shell_v2.
    let legacy = files.lock().unwrap().legacy_root_alias;
    let features = if legacy { "" } else { "shell_v2,stat_v2,ls_v2" };
    let skip_checksum = !legacy && connect.arg0 >= protocol::VERSION;
    Frame::new(
        protocol::CNXN,
        if legacy {
            protocol::LEGACY_VERSION
        } else {
            protocol::VERSION
        },
        4096,
        format!("device::features={features};\0").into_bytes(),
    )
    .write(&mut socket)
    .await?;
    let mut streams = HashMap::<u32, Stream>::new();
    let mut deployed = HashMap::<String, Vec<u8>>::new();
    let mut directories = HashSet::<String>::new();
    while let Ok(frame) = Frame::read(&mut socket, 4096, skip_checksum).await {
        match frame.command {
            protocol::OPEN => {
                let id = frame.arg0;
                Frame::new(protocol::OKAY, id, id, vec![])
                    .write(&mut socket)
                    .await?;
                let service = std::str::from_utf8(&frame.payload)
                    .unwrap()
                    .trim_end_matches('\0');
                let mut stream = if service == "sync:" {
                    Stream::new(Service::Sync(Sync::default()))
                } else if let Some(command) = service.strip_prefix("exec:") {
                    if command.contains("__INTEROP_DEPLOYED__") {
                        let directory = command
                            .split("if mkdir ")
                            .nth(1)
                            .unwrap()
                            .split(';')
                            .next()
                            .unwrap()
                            .to_owned();
                        Stream::new(Service::Deployment {
                            directory,
                            created: false,
                        })
                    } else if command.contains("__INTEROP_READY__") {
                        let mut stream = Stream::new(Service::Helper(Helper::default()));
                        stream.queue(b"__INTEROP_READY__\n", false);
                        stream
                    } else {
                        let mut stream = Stream::new(Service::Plain);
                        let data = files.lock().unwrap();
                        if command.contains("INTEROP_ACCESSIBLE") {
                            if !data.blocked {
                                let path = command
                                    .split("[ -r '")
                                    .nth(1)
                                    .unwrap()
                                    .split('\'')
                                    .next()
                                    .unwrap();
                                let allowed = !data.denied.contains(path);
                                stream
                                    .queue(if allowed { b"INTEROP_ACCESSIBLE" } else { b"" }, true);
                            }
                        } else {
                            panic!("unexpected raw gallery service: {command}");
                        }
                        stream
                    }
                } else {
                    let (command, v2) = if let Some(command) = service.strip_prefix("shell,v2,raw:")
                    {
                        (command, true)
                    } else {
                        (
                            service
                                .strip_prefix("shell:")
                                .expect("known gallery service"),
                            false,
                        )
                    };
                    let output: &[u8] = if command.contains("getprop ro.product.cpu.abi") {
                        b"x86_64\nx86_64\n".as_slice()
                    } else if command.contains("interop-capability-check") {
                        b"interop-capability-check"
                    } else {
                        b""
                    };
                    let mut stream = Stream::new(Service::Plain);
                    if v2 {
                        let mut reply = vec![1];
                        reply.extend_from_slice(&(output.len() as u32).to_le_bytes());
                        reply.extend_from_slice(output);
                        reply.extend_from_slice(&[3, 1, 0, 0, 0, 0]);
                        stream.queue(&reply, true);
                    } else {
                        stream.queue(output, true);
                    }
                    stream
                };
                stream.awaiting_ack = false;
                streams.insert(id, stream);
            }
            protocol::WRTE => {
                let id = frame.arg0;
                Frame::new(protocol::OKAY, id, id, vec![])
                    .write(&mut socket)
                    .await?;
                if let Some(stream) = streams.get_mut(&id) {
                    let (bytes, close) = match &mut stream.service {
                        Service::Sync(sync) => (
                            sync.receive(&frame.payload, &files, &mut deployed, &directories),
                            false,
                        ),
                        Service::Helper(helper) => {
                            // The complete read-back transcript must have
                            // been sent before authorization can arrive. ACKs
                            // in the other direction remain independent.
                            if helper.request.is_some() {
                                assert!(stream.outgoing.is_empty());
                            }
                            helper.receive(&frame.payload, &files, &deployed)
                        }
                        Service::Deployment { directory, created } => {
                            if !*created {
                                assert_eq!(frame.payload, b"create\n");
                                *created = directories.insert(directory.clone());
                                if *created {
                                    (b"__INTEROP_DEPLOYED__\n".to_vec(), false)
                                } else {
                                    (b"__INTEROP_COLLISION__\n".to_vec(), true)
                                }
                            } else {
                                assert_eq!(frame.payload, b"\n");
                                deployed.remove(&format!("{directory}/rename"));
                                directories.remove(directory);
                                (Vec::new(), true)
                            }
                        }
                        Service::Plain => panic!("unexpected service input"),
                    };
                    stream.queue(&bytes, close);
                }
            }
            protocol::OKAY => {
                if let Some(stream) = streams.get_mut(&frame.arg1) {
                    stream.awaiting_ack = false;
                }
            }
            protocol::CLSE => {
                if let Some(stream) = streams.remove(&frame.arg0) {
                    if let Service::Deployment {
                        directory,
                        created: true,
                    } = stream.service
                    {
                        deployed.remove(&format!("{directory}/rename"));
                        directories.remove(&directory);
                    }
                    Frame::new(protocol::CLSE, frame.arg0, frame.arg0, vec![])
                        .write(&mut socket)
                        .await?;
                }
            }
            _ => panic!("unexpected fixture command"),
        }
        let mut closed = Vec::new();
        for (&id, stream) in &mut streams {
            if stream.awaiting_ack {
                continue;
            }
            if let Some(payload) = stream.outgoing.pop_front() {
                Frame::new(protocol::WRTE, id, id, payload)
                    .write(&mut socket)
                    .await?;
                stream.awaiting_ack = true;
            } else if stream.close {
                Frame::new(protocol::CLSE, id, id, vec![])
                    .write(&mut socket)
                    .await?;
                closed.push(id);
            }
        }
        for id in closed {
            streams.remove(&id);
        }
    }
    Ok(())
}

fn normalized(path: &str) -> &str {
    path.strip_suffix("/.").unwrap_or(path)
}

fn node(files: &DeviceFiles, path: &str) -> Option<Node> {
    let mut node = files.nodes.get(normalized(path))?.clone();
    if files.legacy_root_alias && path == "/sdcard" {
        node.mode = 0o120777;
    }
    Some(node)
}

fn children(files: &DeviceFiles, path: &str) -> Vec<(Vec<u8>, Node)> {
    let path = normalized(path);
    let prefix = format!("{path}/");
    let mut result = files
        .nodes
        .iter()
        .filter_map(|(path, node)| {
            Some((
                path.strip_prefix(&prefix)
                    .filter(|name| !name.contains('/'))?
                    .as_bytes()
                    .to_vec(),
                node.clone(),
            ))
        })
        .collect::<Vec<_>>();
    if path == "/sdcard" {
        result.extend(files.raw_root_names.iter().cloned().map(|name| {
            (
                name,
                Node {
                    mode: 0o100644,
                    modified: 10,
                    size: 123,
                },
            )
        }));
    }
    result
}

fn stat_body(node: Option<&Node>, length: usize) -> Vec<u8> {
    let mut body = vec![0; length];
    if let Some(node) = node {
        body[20..24].copy_from_slice(&node.mode.to_le_bytes());
        body[36..44].copy_from_slice(&node.size.to_le_bytes());
        body[52..60].copy_from_slice(&i64::from(node.modified).to_le_bytes());
    } else {
        body[..4].copy_from_slice(&2u32.to_le_bytes());
    }
    body
}

#[derive(Default)]
struct Sync {
    buffered: Vec<u8>,
    upload: Option<(String, Vec<u8>)>,
}
impl Sync {
    fn receive(
        &mut self,
        bytes: &[u8],
        files: &Arc<Mutex<DeviceFiles>>,
        deployed: &mut HashMap<String, Vec<u8>>,
        directories: &HashSet<String>,
    ) -> Vec<u8> {
        self.buffered.extend_from_slice(bytes);
        let mut reply = Vec::new();
        while self.buffered.len() >= 8 {
            let id: [u8; 4] = self.buffered[..4].try_into().unwrap();
            let value = u32::from_le_bytes(self.buffered[4..8].try_into().unwrap()) as usize;
            let length = if &id == b"DONE" { 0 } else { value };
            if self.buffered.len() < 8 + length {
                break;
            }
            let payload = self.buffered[8..8 + length].to_vec();
            self.buffered.drain(..8 + length);
            match &id {
                b"SEND" => {
                    let destination = std::str::from_utf8(&payload).unwrap();
                    let (path, mode) = destination.rsplit_once(',').unwrap();
                    assert_eq!(mode.parse::<u32>().unwrap(), 0o100700);
                    assert!(path.ends_with("/rename"));
                    assert!(directories.contains(path.rsplit_once('/').unwrap().0));
                    self.upload = Some((path.to_owned(), Vec::new()));
                }
                b"DATA" => {
                    assert!(length <= 65536);
                    self.upload.as_mut().unwrap().1.extend_from_slice(&payload);
                }
                b"DONE" => {
                    let (path, bytes) = self.upload.take().unwrap();
                    assert!(bytes.starts_with(b"\x7fELF") && bytes.len() > 100_000);
                    deployed.insert(path, bytes);
                    reply.extend_from_slice(b"OKAY\0\0\0\0");
                }
                b"STAT" | b"LST2" | b"STA2" => {
                    let path = std::str::from_utf8(&payload).unwrap();
                    let files = files.lock().unwrap();
                    let node = if &id == b"STA2" {
                        // STA2 follows the modeled storage alias; LST2 and
                        // legacy STAT retain its symlink identity.
                        files.nodes.get(normalized(path)).cloned()
                    } else {
                        node(&files, path)
                    };
                    reply.extend_from_slice(&id);
                    if &id == b"STAT" {
                        reply.extend_from_slice(
                            &node.as_ref().map_or(0, |node| node.mode).to_le_bytes(),
                        );
                        reply.extend_from_slice(
                            &(node.as_ref().map_or(0, |node| node.size) as u32).to_le_bytes(),
                        );
                        reply.extend_from_slice(
                            &node.as_ref().map_or(0, |node| node.modified).to_le_bytes(),
                        );
                    } else {
                        reply.extend(stat_body(node.as_ref(), 68));
                    }
                }
                b"LIST" | b"LIS2" => {
                    let path = normalized(std::str::from_utf8(&payload).unwrap());
                    let mut files = files.lock().unwrap();
                    if files.list_failures.contains(path) {
                        reply.extend_from_slice(b"FAIL\x06\0\0\0denied");
                    } else {
                        let v2 = &id == b"LIS2";
                        if !files.denied.contains(path) {
                            for (name, node) in children(&files, path).into_iter().rev() {
                                if v2 {
                                    reply.extend_from_slice(b"DNT2");
                                    let mut body = stat_body(Some(&node), 72);
                                    body[68..72]
                                        .copy_from_slice(&(name.len() as u32).to_le_bytes());
                                    reply.extend(body);
                                } else {
                                    reply.extend_from_slice(b"DENT");
                                    reply.extend_from_slice(&node.mode.to_le_bytes());
                                    reply.extend_from_slice(&(node.size as u32).to_le_bytes());
                                    reply.extend_from_slice(&node.modified.to_le_bytes());
                                    reply.extend_from_slice(&(name.len() as u32).to_le_bytes());
                                }
                                reply.extend(name);
                            }
                        }
                        reply.extend_from_slice(b"DONE");
                        reply.extend(vec![0; if v2 { 72 } else { 16 }]);
                        if files.changed_on_list.remove(path) {
                            files.nodes.get_mut(path).unwrap().modified += 1;
                        }
                    }
                }
                _ => panic!("unexpected sync request {id:?}"),
            }
        }
        reply
    }
}

struct Request {
    operation: String,
    source: String,
    limit: usize,
    authorization: String,
}
#[derive(Default)]
struct Helper {
    buffered: Vec<u8>,
    length: Option<usize>,
    request: Option<Request>,
}
impl Helper {
    fn receive(
        &mut self,
        bytes: &[u8],
        files: &Arc<Mutex<DeviceFiles>>,
        deployed: &HashMap<String, Vec<u8>>,
    ) -> (Vec<u8>, bool) {
        self.buffered.extend_from_slice(bytes);
        if let Some(request) = self.request.take() {
            let Some(end) = self.buffered.iter().position(|byte| *byte == b'\n') else {
                self.request = Some(request);
                return (Vec::new(), false);
            };
            assert_eq!(&self.buffered[..end], request.authorization.as_bytes());
            return (
                serde_json::to_vec(&metadata(files, &request)).unwrap(),
                true,
            );
        }
        if self.length.is_none() {
            let Some(end) = self.buffered.iter().position(|byte| *byte == b'\n') else {
                return (Vec::new(), false);
            };
            let length = std::str::from_utf8(&self.buffered[..end])
                .unwrap()
                .parse()
                .unwrap();
            assert!((1..65536).contains(&length));
            self.length = Some(length);
            self.buffered.drain(..=end);
        }
        let length = self.length.unwrap();
        if self.buffered.len() < length {
            return (Vec::new(), false);
        }
        let script = std::str::from_utf8(&self.buffered[..length]).unwrap();
        let assignment = |variable: &str| {
            let prefix = format!("{variable}=$(print -n -- '");
            let encoded = script
                .lines()
                .find_map(|line| line.strip_prefix(&prefix))
                .unwrap()
                .split('\'')
                .next()
                .unwrap()
                .strip_suffix('.')
                .unwrap();
            let bytes = encoded
                .as_bytes()
                .as_chunks::<5>()
                .0
                .iter()
                .map(|chunk| {
                    assert_eq!(&chunk[..2], b"\\0");
                    u8::from_str_radix(std::str::from_utf8(&chunk[2..]).unwrap(), 8).unwrap()
                })
                .collect::<Vec<_>>();
            String::from_utf8(bytes).unwrap()
        };
        let path = script
            .lines()
            .find_map(|line| line.strip_prefix("exec 0<"))
            .unwrap()
            .split_whitespace()
            .next()
            .unwrap();
        let marker = script
            .lines()
            .find_map(|line| line.strip_prefix("print -r -- '"))
            .unwrap()
            .split('\'')
            .next()
            .unwrap();
        assert!(marker.starts_with("__INTEROP_VERIFIED_"));
        let authorization = script
            .lines()
            .find_map(|line| line.strip_prefix("[ \"$authorization\" = '"))
            .unwrap()
            .split('\'')
            .next()
            .unwrap()
            .to_owned();
        let operation = script
            .lines()
            .find_map(|line| line.strip_prefix("exec /proc/self/fd/0 "))
            .unwrap()
            .split_whitespace()
            .next()
            .unwrap()
            .to_owned();
        self.request = Some(Request {
            operation,
            source: assignment("source"),
            limit: assignment("target").parse().unwrap(),
            authorization,
        });
        let mut output = deployed
            .get(path)
            .expect("execute only the already uploaded artifact")
            .clone();
        output.extend_from_slice(marker.as_bytes());
        output.push(b'\n');
        self.buffered.drain(..length);
        (output, false)
    }
}

fn metadata(files: &Arc<Mutex<DeviceFiles>>, request: &Request) -> Value {
    let mut files = files.lock().unwrap();
    let path = normalized(&request.source);
    if request.operation != "list" {
        assert!(matches!(request.operation.as_str(), "stat" | "lstat"));
        let stat = if request.operation == "stat" {
            files.nodes.get(path).cloned()
        } else {
            node(&files, &request.source)
        };
        return match stat {
            Some(node) => {
                json!({"protocol":1,"ok":true,"errno":0,"mode":node.mode,"size":node.size,"modifiedSeconds":node.modified})
            }
            None => json!({"protocol":1,"ok":false,"errno":2}),
        };
    }
    if files.denied.contains(path) {
        return json!({"protocol":1,"ok":false,"errno":13});
    }
    if !node(&files, &request.source).is_some_and(|node| node.mode & 0o170000 == 0o040000) {
        return json!({"protocol":1,"ok":false,"errno":20});
    }
    let children = children(&files, path);
    let truncated = children.len() > request.limit;
    let entries = children.into_iter().take(request.limit).map(|(name, node)| {
        let name = name.iter().map(|byte| format!("{byte:02x}")).collect::<String>();
        let errno = if files.fallback_metadata_failure && files.list_failures.contains(path) { 13 } else { 0 };
        if errno == 0 {
            json!({"nameHex":name,"mode":node.mode,"size":node.size,"modifiedSeconds":node.modified,"errno":0})
        } else {
            json!({"nameHex":name,"mode":0,"size":0,"modifiedSeconds":0,"errno":errno})
        }
    }).collect::<Vec<_>>();
    if files.changed_on_list.remove(path) {
        files.nodes.get_mut(path).unwrap().modified += 1;
    }
    json!({"protocol":1,"entries":entries,"truncated":truncated,"ok":true,"errno":0})
}
