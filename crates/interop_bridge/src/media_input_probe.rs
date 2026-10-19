//! PROTOTYPE ONLY: fixed-fixture HTTP vs MDK appendBuffer input experiment.
//!
//! Not a production input/backpressure API. One immutable fixture (at most
//! 32 MiB) is deliberately retained until process exit: MDK's append ownership
//! contract has not been established. Later opens must provide identical bytes.
//! Never reset/delete/construct a player here. The caller lends a LIVE fvp
//! nativeHandle and must cancel, poll `finished`, then release BEFORE disposing
//! its player. Cancellation cannot interrupt an unknown blocking MDK call.
//! Caller serializes player setup/disposal with these exports. Raw pointers must
//! be valid for their stated extent; version/size guards are not pointer probes.
//!
//! C ABI tail transcribed from fvp 0.39.1's MDK 0.39.0 c/Player.h; prefix is
//! shared with media_trace. Copyright (c) 2019-2026 WangBin
//! <wbsecg1 at gmail.com>. MDK SDK: https://github.com/wang-bin/mdk-sdk.
//! Free for opensource softwares or non-commercial use. The above copyright
//! notice and this permission notice shall be included in all copies or
//! substantial portions of the Software.

use crate::media_trace::PlayerApi;
use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void};
use std::io::{Read, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::ops::Range;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

const MAX_FIXTURE: usize = 32 * 1024 * 1024;
const MAX_CHUNKS: usize = 4096;
const CLOSED: i32 = -1;
const FAILED: i32 = -2;
const CAPACITY: i32 = -3;
const POLL: Duration = Duration::from_millis(5);

#[repr(C)]
struct SyncCallback {
    cb: Option<unsafe extern "C" fn(*mut c_void) -> f64>,
    opaque: *mut c_void,
}

#[repr(C)]
struct LoopCallback {
    cb: Option<unsafe extern "C" fn(c_int, *mut c_void)>,
    opaque: *mut c_void,
}

#[repr(C)]
struct MediaStatusCallback {
    cb: Option<unsafe extern "C" fn(u32, u32, *mut c_void) -> bool>,
    opaque: *mut c_void,
}

#[repr(C)]
union ApiSize {
    reserved: *mut c_void,
    size: c_int,
}

type Append = unsafe extern "C" fn(*mut c_void, *const u8, usize, c_int) -> bool;

// All intervening slots are typed, rather than guessed pointer-array offsets.
#[repr(C)]
#[allow(dead_code)]
struct InputApi {
    prefix: PlayerApi,
    set_property: Option<unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char)>,
    get_property: Option<unsafe extern "C" fn(*mut c_void, *const c_char) -> *const c_char>,
    record: Option<unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char)>,
    set_loop_range: Option<unsafe extern "C" fn(*mut c_void, c_int, i64, i64)>,
    set_loop: Option<unsafe extern "C" fn(*mut c_void, c_int)>,
    on_loop: Option<unsafe extern "C" fn(*mut c_void, LoopCallback, *mut u64)>,
    set_range: Option<unsafe extern "C" fn(*mut c_void, i64, i64)>,
    set_render_api: Option<unsafe extern "C" fn(*mut c_void, *const c_void, *mut c_void)>,
    render_api: Option<unsafe extern "C" fn(*mut c_void, *mut c_void) -> *mut c_void>,
    map_point:
        Option<unsafe extern "C" fn(*mut c_void, c_int, *mut f32, *mut f32, *mut f32, *mut c_void)>,
    on_sync: Option<unsafe extern "C" fn(*mut c_void, SyncCallback, c_int)>,
    set_video_effect: Option<unsafe extern "C" fn(*mut c_void, c_int, *const f32, *mut c_void)>,
    set_active_tracks: Option<unsafe extern "C" fn(*mut c_void, c_int, *const c_int, usize)>,
    set_decoders: Option<unsafe extern "C" fn(*mut c_void, c_int, *mut *const c_char)>,
    set_channel_volume: Option<unsafe extern "C" fn(*mut c_void, f32, c_int)>,
    set_frame_rate: Option<unsafe extern "C" fn(*mut c_void, f32)>,
    set_point_map:
        Option<unsafe extern "C" fn(*mut c_void, *const f32, *const f32, c_int, *mut c_void)>,
    set_color_space: Option<unsafe extern "C" fn(*mut c_void, c_int, *mut c_void)>,
    on_media_status: Option<unsafe extern "C" fn(*mut c_void, MediaStatusCallback, *mut u64)>,
    runtime_size: ApiSize,
    enqueue_video: Option<unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void)>,
    buffered_time_ranges: Option<unsafe extern "C" fn(*mut c_void, *mut i64, c_int) -> c_int>,
    append_buffer: Option<Append>,
}

struct Chunk {
    pts_us: u64,
    range: Range<usize>,
}

struct Fixture {
    bytes: Vec<u8>,
    chunks: Vec<Chunk>,
}

#[derive(Clone)]
struct SendMetric {
    index: usize,
    pts_us: u64,
    entered_us: u64,
    completed_us: u64,
    bytes: usize,
    accepted: bool,
}

#[derive(Default)]
struct State {
    started: bool,
    started_us: u64,
    ended_us: u64,
    feed_complete: bool,
    error: Option<String>,
    sends: Vec<SendMetric>,
    handle: Option<JoinHandle<()>>,
    rss_start_kib: Option<u64>,
    rss_end_kib: Option<u64>,
}

struct Probe {
    created_us: u64,
    player: u64,
    object: usize,
    append: Append,
    mode: i32,
    url: Option<String>,
    secret: String,
    listener: Mutex<Option<TcpListener>>,
    fixture: Arc<Fixture>,
    cancelled: AtomicBool,
    in_flight: AtomicU32,
    state: Mutex<State>,
}

static FIXTURE: OnceLock<Mutex<Option<Arc<Fixture>>>> = OnceLock::new();
static REGISTRY: OnceLock<Mutex<HashMap<u64, Arc<Probe>>>> = OnceLock::new();
static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);

fn registry() -> &'static Mutex<HashMap<u64, Arc<Probe>>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn now() -> u64 {
    interop_core::media::monotonic_micros()
}

fn next_token() -> Option<u64> {
    let mut current = NEXT_TOKEN.load(Ordering::Relaxed);
    loop {
        let next = current.checked_add(1)?;
        match NEXT_TOKEN.compare_exchange_weak(current, next, Ordering::Relaxed, Ordering::Relaxed)
        {
            Ok(_) => return Some(current),
            Err(actual) => current = actual,
        }
    }
}

fn ffi<T>(failure: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(failure)
}

fn parse_fixture(bytes: Vec<u8>) -> Option<Fixture> {
    if bytes.len() < 8 || &bytes[..4] != b"MDKP" {
        return None;
    }
    let count = u32::from_be_bytes(bytes[4..8].try_into().ok()?) as usize;
    if !(1..=MAX_CHUNKS).contains(&count) {
        return None;
    }
    let mut offset: usize = 8;
    let mut chunks = Vec::with_capacity(count);
    let mut previous = 0;
    for index in 0..count {
        let fields = bytes.get(offset..offset.checked_add(12)?)?;
        let pts_us = u64::from_be_bytes(fields[..8].try_into().ok()?);
        let length = u32::from_be_bytes(fields[8..].try_into().ok()?) as usize;
        offset += 12;
        let end = offset.checked_add(length)?;
        if length == 0 || end > bytes.len() || pts_us < previous || (index == 0 && pts_us != 0) {
            return None;
        }
        chunks.push(Chunk {
            pts_us,
            range: offset..end,
        });
        previous = pts_us;
        offset = end;
    }
    (offset == bytes.len()).then_some(Fixture { bytes, chunks })
}

unsafe fn fixed_fixture(data: *const u8, len: u32) -> Option<Arc<Fixture>> {
    if data.is_null() || len as usize > MAX_FIXTURE || len < 8 {
        return None;
    }
    // SAFETY: caller lends len readable bytes throughout open; no pointer retained.
    let input = unsafe { std::slice::from_raw_parts(data, len as usize) };
    let mut fixed = FIXTURE.get_or_init(|| Mutex::new(None)).lock().ok()?;
    if let Some(fixture) = &*fixed {
        return (fixture.bytes == input).then(|| fixture.clone());
    }
    let fixture = Arc::new(parse_fixture(input.to_vec())?);
    *fixed = Some(fixture.clone());
    Some(fixture)
}

unsafe fn player_api(player: u64, version: i32) -> Option<(usize, Append)> {
    if version & !0xff != 0x2700
        || player == 0
        || usize::try_from(player).is_err()
        || !player.is_multiple_of(std::mem::align_of::<InputApi>() as u64)
    {
        return None;
    }
    let api = player as usize as *const InputApi;
    // SAFETY: version 0.39 supplies the legacy prefix including the size union.
    // Do not form a reference to the extended table until its size is checked.
    let size = unsafe { ptr::addr_of!((*api).runtime_size.size).read() };
    let required =
        std::mem::offset_of!(InputApi, append_buffer) + std::mem::size_of::<Option<Append>>();
    if size <= 0 || (size as usize) < required {
        return None;
    }
    let object = unsafe { ptr::addr_of!((*api).prefix.object).read() };
    let append = unsafe { ptr::addr_of!((*api).append_buffer).read() }?;
    (!object.is_null()).then_some((object as usize, append))
}

/// Returns a token, or 0 on invalid version/table/fixture, duplicate owner, or IO failure.
/// mode: 0 = loopback HTTP; 1 = appendBuffer. Open does not feed any bytes.
/// # Safety
/// player and data must satisfy the live handle and readable buffer contracts above.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn input_probe_open(
    player: u64,
    version: i32,
    mode: i32,
    data: *const u8,
    len: u32,
) -> u64 {
    ffi(0, || {
        if mode != 0 && mode != 1 {
            return 0;
        }
        let Some((object, append)) = (unsafe { player_api(player, version) }) else {
            return 0;
        };
        let Some(fixture) = (unsafe { fixed_fixture(data, len) }) else {
            return 0;
        };
        let secret = uuid::Uuid::new_v4().simple().to_string();
        let (listener, url) = if mode == 0 {
            let Ok(listener) = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)) else {
                return 0;
            };
            if listener.set_nonblocking(true).is_err() {
                return 0;
            }
            let Ok(address) = listener.local_addr() else {
                return 0;
            };
            (
                Some(listener),
                Some(format!("http://127.0.0.1:{}/{secret}", address.port())),
            )
        } else {
            (None, None)
        };
        let Ok(mut registry) = registry().lock() else {
            return 0;
        };
        if registry.len() >= 4 || registry.values().any(|probe| probe.player == player) {
            return 0;
        }
        let Some(token) = next_token() else {
            return 0;
        };
        registry.insert(
            token,
            Arc::new(Probe {
                created_us: now(),
                player,
                object,
                append,
                mode,
                url,
                secret,
                listener: Mutex::new(listener),
                fixture,
                cancelled: AtomicBool::new(false),
                in_flight: AtomicU32::new(0),
                state: Mutex::new(State::default()),
            }),
        );
        token
    })
}

fn rss_kib() -> Option<u64> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    status.lines().find_map(|line| {
        line.strip_prefix("VmRSS:")?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    })
}

fn cancelled(probe: &Probe) -> bool {
    probe.cancelled.load(Ordering::Acquire)
}

fn authenticate(probe: &Probe, listener: TcpListener) -> Result<Option<TcpStream>, String> {
    let awaiting = Instant::now();
    let mut attempts = 0;
    while !cancelled(probe) {
        if awaiting.elapsed() > Duration::from_secs(20) {
            return Err("HTTP consumer connect timeout".into());
        }
        let (mut stream, _) = match listener.accept() {
            Ok(connection) => connection,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(POLL);
                continue;
            }
            Err(error) => return Err(error.to_string()),
        };
        stream
            .set_nodelay(true)
            .map_err(|error| error.to_string())?;
        stream
            .set_read_timeout(Some(Duration::from_millis(10)))
            .map_err(|error| error.to_string())?;
        stream
            .set_write_timeout(Some(Duration::from_millis(250)))
            .map_err(|error| error.to_string())?;
        let mut request = Vec::new();
        let reading = Instant::now();
        while !cancelled(probe)
            && reading.elapsed() < Duration::from_secs(2)
            && request.len() < 4096
        {
            let mut byte = [0];
            match stream.read(&mut byte) {
                Ok(1) => {
                    request.push(byte[0]);
                    if request.ends_with(b"\r\n\r\n") {
                        break;
                    }
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    continue;
                }
                _ => break,
            }
        }
        if cancelled(probe) {
            return Ok(None);
        }
        if request.starts_with(format!("GET /{} HTTP/1.", probe.secret).as_bytes())
            && request.ends_with(b"\r\n\r\n")
        {
            stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: video/x-matroska\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").map_err(|error| error.to_string())?;
            return Ok(Some(stream));
        }
        let _ = stream
            .write_all(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        attempts += 1;
        if attempts == 8 {
            return Err("HTTP authentication failed".into());
        }
    }
    Ok(None)
}

fn run(probe: &Probe) -> Result<(), String> {
    let mut stream = if probe.mode == 0 {
        let listener = probe
            .listener
            .lock()
            .map_err(|_| "listener lock poisoned")?
            .take()
            .ok_or("missing HTTP listener")?;
        match authenticate(probe, listener)? {
            Some(stream) => Some(stream),
            None => return Ok(()),
        }
    } else {
        None
    };
    if cancelled(probe) {
        return Ok(());
    }
    let source_start = Instant::now();
    {
        let mut state = probe.state.lock().map_err(|_| "state lock poisoned")?;
        state.started_us = now();
        state.rss_start_kib = rss_kib();
    }
    for (index, chunk) in probe.fixture.chunks.iter().enumerate() {
        while source_start.elapsed().as_micros() < u128::from(chunk.pts_us) {
            if cancelled(probe) {
                return Ok(());
            }
            let remaining =
                u128::from(chunk.pts_us).saturating_sub(source_start.elapsed().as_micros());
            thread::sleep(Duration::from_micros(remaining.min(5000) as u64));
        }
        // Cancellation and native admission share this short lock. An admitted
        // MDK call can outlive cancel; release must observe actual thread exit.
        {
            let _admission = probe.state.lock().map_err(|_| "state lock poisoned")?;
            if cancelled(probe) {
                return Ok(());
            }
            if probe.mode == 1 {
                probe.in_flight.store(1, Ordering::Release);
            }
        }
        let data = &probe.fixture.bytes[chunk.range.clone()];
        let entered_us = now();
        let result =
            if let Some(stream) = &mut stream {
                // Match the existing HTTP adapter's three write_all calls per chunk.
                stream
                    .write_all(format!("{:x}\r\n", data.len()).as_bytes())
                    .and_then(|_| stream.write_all(data))
                    .and_then(|_| stream.write_all(b"\r\n"))
                    .map(|_| true)
                    .map_err(|error| error.to_string())
            } else {
                // SAFETY: fvp keeps object live until worker exit. The immutable
                // fixture is process-retained, including after false returns/cancel.
                Ok(unsafe {
                    (probe.append)(probe.object as *mut c_void, data.as_ptr(), data.len(), 0)
                })
            };
        let completed_us = now();
        probe.in_flight.store(0, Ordering::Release);
        let accepted = matches!(result, Ok(true));
        let mut state = probe.state.lock().map_err(|_| "state lock poisoned")?;
        state.sends.push(SendMetric {
            index,
            pts_us: chunk.pts_us,
            entered_us,
            completed_us,
            bytes: data.len(),
            accepted,
        });
        drop(state);
        result?;
    }
    {
        let mut state = probe.state.lock().map_err(|_| "state lock poisoned")?;
        state.feed_complete = true;
        state.ended_us = now();
        state.rss_end_kib = rss_kib();
    }
    // Neither input sends an EOF sentinel. Preserve the HTTP consumer's input
    // until cancel, rather than crediting an EOF difference as a speed gain.
    if let Some(stream) = stream {
        while !cancelled(probe) {
            thread::sleep(POLL);
        }
        let _ = stream.shutdown(Shutdown::Both);
    }
    Ok(())
}

/// 1 = started, 0 = already started/cancelled, negative = invalid token/failure.
#[unsafe(no_mangle)]
pub extern "C" fn input_probe_start(token: u64) -> i32 {
    ffi(FAILED, || {
        let Ok(registry) = registry().lock() else {
            return FAILED;
        };
        let Some(probe) = registry.get(&token) else {
            return CLOSED;
        };
        let Ok(mut state) = probe.state.lock() else {
            return FAILED;
        };
        if state.started || cancelled(probe) {
            return 0;
        }
        state.started = true;
        let worker = probe.clone();
        match thread::Builder::new()
            .name("mdk-input-PROTOTYPE".into())
            .spawn(move || {
                let result = catch_unwind(AssertUnwindSafe(|| run(&worker)));
                if let Ok(mut state) = worker.state.lock() {
                    state.error = match result {
                        Ok(Ok(())) => None,
                        Ok(Err(error)) => Some(error),
                        Err(_) => Some("native input worker panicked".into()),
                    };
                    if state.ended_us == 0 {
                        state.ended_us = now();
                    }
                    if state.rss_end_kib.is_none() {
                        state.rss_end_kib = rss_kib();
                    }
                }
            }) {
            Ok(handle) => {
                state.handle = Some(handle);
                1
            }
            Err(error) => {
                state.error = Some(error.to_string());
                state.ended_us = now();
                FAILED
            }
        }
    })
}

/// JSON bytes written, or -1 invalid token / -2 internal failure / -3 capacity.
/// `finished` means the worker actually exited, not just a cancellation request.
/// `feedComplete` means every chunk was attempted (inspect accepted/rejected).
/// # Safety
/// out must be writable for cap bytes and must not alias the player or fixture.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn input_probe_metrics(token: u64, out: *mut u8, cap: u32) -> i32 {
    ffi(FAILED, || {
        let probe = match registry().lock() {
            Ok(registry) => registry.get(&token).cloned(),
            Err(_) => return FAILED,
        };
        let Some(probe) = probe else {
            return CLOSED;
        };
        let Ok(state) = probe.state.lock() else {
            return FAILED;
        };
        let finished = state
            .handle
            .as_ref()
            .map_or(state.started || cancelled(&probe), JoinHandle::is_finished);
        let started = state.started;
        let started_us = state.started_us;
        let ended_us = state.ended_us;
        let feed_complete = state.feed_complete;
        let error = state.error.clone();
        let rss_start = state.rss_start_kib;
        let rss_end = state.rss_end_kib;
        let records = state.sends.clone();
        drop(state); // JSON allocation/formatting must not block native admission.
        let sends: Vec<_> = records.iter().map(|send| serde_json::json!({
            "index": send.index, "ptsUs": send.pts_us, "enteredUs": send.entered_us, "completedUs": send.completed_us,
            "bytes": send.bytes, "accepted": send.accepted,
        })).collect();
        let accepted = records.iter().filter(|send| send.accepted).count();
        let wall_elapsed = if started_us == 0 {
            0
        } else {
            (if ended_us == 0 { now() } else { ended_us }).saturating_sub(started_us)
        };
        let value = serde_json::json!({
            "prototype": true, "mode": if probe.mode == 0 { "http" } else { "append" },
            "url": probe.url, "createdUs": probe.created_us, "started": started, "startedUs": started_us,
            "finished": finished, "feedComplete": feed_complete, "cancelled": cancelled(&probe),
            "error": error, "nativeCallsInFlight": probe.in_flight.load(Ordering::Acquire),
            "accepted": accepted, "rejected": records.len() - accepted,
            "bytes": records.iter().filter(|send| send.accepted).map(|send| send.bytes as u64).sum::<u64>(),
            "sends": sends, "wallElapsedUs": wall_elapsed,
            "rssStartKiB": rss_start, "rssEndKiB": rss_end,
            "fixtureBytes": probe.fixture.bytes.len(), "fixtureChunks": probe.fixture.chunks.len(),
        });
        let Ok(bytes) = serde_json::to_vec(&value) else {
            return FAILED;
        };
        if out.is_null() || bytes.len() > cap as usize || bytes.len() > i32::MAX as usize {
            return CAPACITY;
        }
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
        }
        bytes.len() as i32
    })
}

/// Revokes future admission; never waits for a native call or joins the worker.
#[unsafe(no_mangle)]
pub extern "C" fn input_probe_cancel(token: u64) -> i32 {
    ffi(FAILED, || {
        let Ok(registry) = registry().lock() else {
            return FAILED;
        };
        let Some(probe) = registry.get(&token) else {
            return CLOSED;
        };
        let Ok(_admission) = probe.state.lock() else {
            return FAILED;
        };
        probe.cancelled.store(true, Ordering::Release);
        1
    })
}

/// 1 removed; 0 worker still alive; negative invalid token/internal failure.
/// A true worker completion is required; a native timeout never proves drain.
#[unsafe(no_mangle)]
pub extern "C" fn input_probe_release(token: u64) -> i32 {
    ffi(FAILED, || {
        let Ok(mut registry) = registry().lock() else {
            return FAILED;
        };
        let Some(probe) = registry.get(&token) else {
            return CLOSED;
        };
        let Ok(mut state) = probe.state.lock() else {
            return FAILED;
        };
        if state
            .handle
            .as_ref()
            .is_some_and(|handle| !handle.is_finished())
            || probe.in_flight.load(Ordering::Acquire) != 0
        {
            return 0;
        }
        if let Some(handle) = state.handle.take() {
            let _ = handle.join();
        }
        drop(state);
        registry.remove(&token);
        1
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::sync::mpsc;

    fn fixture_bytes() -> Vec<u8> {
        let mut bytes = b"MDKP".to_vec();
        bytes.extend_from_slice(&3_u32.to_be_bytes());
        for (pts, payload) in [
            (0_u64, b"header".as_slice()),
            (0, b"first"),
            (5_000, b"last"),
        ] {
            bytes.extend_from_slice(&pts.to_be_bytes());
            bytes.extend_from_slice(&(payload.len() as u32).to_be_bytes());
            bytes.extend_from_slice(payload);
        }
        bytes
    }

    #[test]
    fn fixture_parser_rejects_truncation_trailing_data_and_reversed_pts() {
        let bytes = fixture_bytes();
        let parsed = parse_fixture(bytes.clone()).unwrap();
        assert_eq!(parsed.chunks.len(), 3);
        assert_eq!(&parsed.bytes[parsed.chunks[1].range.clone()], b"first");
        for length in 0..bytes.len() {
            assert!(parse_fixture(bytes[..length].to_vec()).is_none());
        }
        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(parse_fixture(trailing).is_none());
        let mut reversed = bytes;
        let second_pts = parsed.chunks[1].range.start - 12;
        reversed[second_pts..second_pts + 8].copy_from_slice(&6_000_u64.to_be_bytes());
        assert!(parse_fixture(reversed).is_none());
    }

    #[test]
    fn typed_tail_matches_c_header_layout() {
        // cc against the installed, unmodified fvp 0.39.1 SDK on x64:
        // sizeof(mdkPlayerAPI)=608, offsetof(size)=544, appendBuffer=568.
        // The Rust transcription intentionally ends immediately after append.
        let pointer = std::mem::size_of::<*mut c_void>();
        assert_eq!(std::mem::offset_of!(InputApi, runtime_size), 68 * pointer);
        assert_eq!(std::mem::offset_of!(InputApi, append_buffer), 71 * pointer);
        assert_eq!(std::mem::size_of::<InputApi>(), 72 * pointer);
    }

    struct Mock {
        calls: AtomicUsize,
        invalid: AtomicBool,
        entered: mpsc::Sender<()>,
        unblock: Mutex<mpsc::Receiver<()>>,
    }

    unsafe extern "C" fn append(
        object: *mut c_void,
        data: *const u8,
        length: usize,
        options: c_int,
    ) -> bool {
        let mock = unsafe { &*object.cast::<Mock>() };
        if data.is_null() || length == 0 || options != 0 {
            mock.invalid.store(true, Ordering::Release);
            return false;
        }
        if mock.calls.fetch_add(1, Ordering::AcqRel) == 0 {
            let _ = mock.entered.send(());
            if let Ok(unblock) = mock.unblock.lock() {
                let _ = unblock.recv();
            }
        }
        true
    }

    fn metrics(token: u64) -> serde_json::Value {
        let mut buffer = vec![0; 1024 * 1024];
        let length =
            unsafe { input_probe_metrics(token, buffer.as_mut_ptr(), buffer.len() as u32) };
        assert!(length > 0);
        serde_json::from_slice(&buffer[..length as usize]).unwrap()
    }

    fn wait_for(token: u64, field: &str) -> serde_json::Value {
        let started = Instant::now();
        loop {
            let value = metrics(token);
            if value[field] == true {
                return value;
            }
            assert!(
                started.elapsed() < Duration::from_secs(2),
                "waiting for {field}: {value}"
            );
            thread::sleep(POLL);
        }
    }

    #[test]
    fn exported_probe_preserves_blocked_call_lifetime_and_http_chunk_semantics() {
        let (entered_tx, entered_rx) = mpsc::channel();
        let (unblock_tx, unblock_rx) = mpsc::channel();
        let mock = Mock {
            calls: AtomicUsize::new(0),
            invalid: AtomicBool::new(false),
            entered: entered_tx,
            unblock: Mutex::new(unblock_rx),
        };
        let mut api: InputApi = unsafe { std::mem::zeroed() };
        api.prefix.object = ptr::from_ref(&mock).cast_mut().cast();
        api.runtime_size.size = std::mem::size_of::<InputApi>() as c_int;
        api.append_buffer = Some(append);
        let bytes = fixture_bytes();
        assert!(unsafe { player_api(1, 0x2600) }.is_none());
        api.runtime_size.size = std::mem::offset_of!(InputApi, append_buffer) as c_int;
        assert!(unsafe { player_api(ptr::from_ref(&api) as usize as u64, 0x2700) }.is_none());
        api.runtime_size.size = std::mem::size_of::<InputApi>() as c_int;
        api.append_buffer = None;
        assert!(unsafe { player_api(ptr::from_ref(&api) as usize as u64, 0x2700) }.is_none());
        api.append_buffer = Some(append);
        let player = ptr::from_ref(&api) as usize as u64;
        let open = |mode| unsafe {
            input_probe_open(player, 0x2700, mode, bytes.as_ptr(), bytes.len() as u32)
        };
        let token = open(1);
        assert_ne!(token, 0);
        assert_eq!(open(1), 0, "duplicate live player owner");
        assert_eq!(mock.calls.load(Ordering::Acquire), 0, "open must not feed");
        assert_eq!(metrics(token)["started"], false);
        let first_fixture = registry().lock().unwrap()[&token].fixture.clone();
        assert_eq!(input_probe_start(token), 1);
        entered_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(input_probe_cancel(token), 1);
        assert_eq!(input_probe_release(token), 0);
        let blocked = metrics(token);
        assert_eq!(blocked["finished"], false);
        assert_eq!(blocked["nativeCallsInFlight"], 1);
        unblock_tx.send(()).unwrap();
        let done = wait_for(token, "finished");
        assert_eq!(done["nativeCallsInFlight"], 0);
        assert_eq!(done["feedComplete"], false);
        assert_eq!(done["sends"].as_array().unwrap().len(), 1);
        assert_eq!(
            mock.calls.load(Ordering::Acquire),
            1,
            "cancel stops subsequent sends"
        );
        assert_eq!(input_probe_release(token), 1);

        let token = open(1);
        assert_ne!(token, 0);
        assert!(Arc::ptr_eq(
            &first_fixture,
            &registry().lock().unwrap()[&token].fixture
        ));
        assert_eq!(input_probe_start(token), 1);
        let done = wait_for(token, "finished");
        assert_eq!(done["feedComplete"], true);
        assert_eq!(done["accepted"], 3);
        assert_eq!(done["sends"][1]["index"], 1);
        assert_eq!(done["sends"][1]["ptsUs"], 0);
        assert_eq!(done["sends"][2]["ptsUs"], 5000);
        assert!(!mock.invalid.load(Ordering::Acquire));
        assert_eq!(input_probe_release(token), 1);
        let mut different = bytes.clone();
        *different.last_mut().unwrap() ^= 1;
        assert_eq!(
            unsafe {
                input_probe_open(
                    player,
                    0x2700,
                    1,
                    different.as_ptr(),
                    different.len() as u32,
                )
            },
            0
        );

        let token = open(0);
        let opened = metrics(token);
        assert_eq!(opened["startedUs"], 0);
        let url = opened["url"]
            .as_str()
            .unwrap()
            .strip_prefix("http://")
            .unwrap();
        let (address, secret) = url.split_once('/').unwrap();
        assert_eq!(input_probe_start(token), 1);
        assert_eq!(
            metrics(token)["startedUs"],
            0,
            "clock waits for HTTP consumer"
        );
        let mut invalid = TcpStream::connect(address).unwrap();
        invalid
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        invalid.write_all(b"GET /wrong HTTP/1.1\r\n\r\n").unwrap();
        let mut denied = Vec::new();
        invalid.read_to_end(&mut denied).unwrap();
        assert!(denied.starts_with(b"HTTP/1.1 403"));
        let mut client = TcpStream::connect(address).unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        client
            .write_all(format!("GET /{secret} HTTP/1.1\r\n\r\n").as_bytes())
            .unwrap();
        let mut expected = b"HTTP/1.1 200 OK\r\nContent-Type: video/x-matroska\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".to_vec();
        expected.extend_from_slice(b"6\r\nheader\r\n5\r\nfirst\r\n4\r\nlast\r\n");
        let mut actual = vec![0; expected.len()];
        client.read_exact(&mut actual).unwrap();
        assert_eq!(actual, expected);
        let complete = wait_for(token, "feedComplete");
        assert_eq!(
            complete["finished"], false,
            "HTTP input stays open until cancel"
        );
        assert_eq!(complete["accepted"], 3);
        client
            .set_read_timeout(Some(Duration::from_millis(30)))
            .unwrap();
        let mut trailing = [0];
        assert!(
            matches!(client.read(&mut trailing), Err(error) if matches!(error.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut)),
            "no EOF or terminating HTTP chunk before cancel"
        );
        assert_eq!(input_probe_cancel(token), 1);
        wait_for(token, "finished");
        assert_eq!(input_probe_release(token), 1);
        assert_eq!(
            unsafe { input_probe_metrics(token, ptr::null_mut(), 0) },
            CLOSED
        );
    }
}
