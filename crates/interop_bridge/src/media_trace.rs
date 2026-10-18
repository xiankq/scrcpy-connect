//! Opt-in MDK diagnostics; these exports are deliberately outside FRB generation.
//!
//! # Foreign caller contract
//! `player` must be the app-owned, live fvp `Player.nativeHandle` (mdkPlayerAPI*),
//! with the supplied version obtained from that same library's MDK_version().
//! Open/snapshot/close are serialized by the owning main isolate. Close BEFORE
//! texture/player disposal; never call these exports with a freed handle. This
//! is not an arbitrary-pointer validation API. Output buffers must be writable
//! for `capacity` bytes and may not alias borrowed MDK objects.
//!
//! No callback calls Dart, retains a borrowed frame, or invokes MDK under a Rust
//! lock. Opaque values are monotonically allocated integers, never Box pointers.
//! Close revokes registry membership; in-flight callbacks own Arc references,
//! and callbacks not yet admitted safely miss the token. We intentionally leave
//! a retired pass-through callback installed until MDK replaces/destroys it:
//! unregister has no documented drain guarantee. The native library containing
//! the trampoline must remain loaded as long as its MDK players can callback.
//!
//! ABI transcription: fvp 0.39.1's installed MDK 0.39.0 SDK,
//! android/mdk-sdk/include/mdk/c/{Player,VideoFrame,global}.h. Official sources:
//! https://github.com/wang-bin/mdk-sdk (SDK headers distributed in releases),
//! https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs . Full typed prefixes are
//! retained through snapshot/timestamp; no guessed byte offsets or C++ ABI.
//! Copyright (c) 2019-2026 WangBin <wbsecg1 at gmail.com>. This file is part of MDK.
//! MDK SDK: https://github.com/wang-bin/mdk-sdk
//! Free for opensource softwares or non-commercial use.
//! The above copyright notice and this permission notice shall be included
//! in all copies or substantial portions of the Software.

use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_int, c_long, c_void};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

const MAX_TRACES: usize = 16;
const MAX_DECODED: usize = 256;
const MAX_SIDE: i32 = 256;
const MAX_SNAPSHOT_BYTES: usize = 256 * 256 * 4;
const MAX_METRICS_BYTES: usize = 65_536;
const SNAPSHOT_TIMEOUT: Duration = Duration::from_secs(5);
const CLOSED: i32 = -1;
const FAILED: i32 = -2;
const CAPACITY: i32 = -3;
const TIMED_OUT: i32 = -4;

#[repr(C)]
#[derive(Clone, Copy)]
struct Callback<F> {
    cb: Option<F>,
    opaque: *mut c_void,
}

type VideoCallback =
    Callback<unsafe extern "C" fn(*mut *mut VideoFrameApi, c_int, *mut c_void) -> c_int>;
type SnapshotCallback =
    Callback<unsafe extern "C" fn(*mut SnapshotRequest, f64, *mut c_void) -> *mut c_char>;
type VoidCallback = Callback<unsafe extern "C" fn(*mut c_void)>;
type TimeoutCallback = Callback<unsafe extern "C" fn(i64, *mut c_void) -> bool>;
type PrepareCallback = Callback<unsafe extern "C" fn(i64, *mut bool, *mut c_void) -> bool>;
type StateCallback = Callback<unsafe extern "C" fn(c_int, *mut c_void)>;
type StatusCallback = Callback<unsafe extern "C" fn(u32, *mut c_void) -> bool>;
type RenderCallback = Callback<unsafe extern "C" fn(*mut c_void, *mut c_void)>;
type AudioCallback = Callback<unsafe extern "C" fn(*mut *mut c_void, c_int, *mut c_void) -> c_int>;
type SeekCallback = Callback<unsafe extern "C" fn(i64, *mut c_void)>;
type BitrateCallback = Callback<unsafe extern "C" fn(bool, *mut c_void)>;
type EventCallback = Callback<unsafe extern "C" fn(*const c_void, *mut c_void) -> bool>;

#[repr(C)]
struct SnapshotRequest {
    data: *mut u8,
    width: c_int,
    height: c_int,
    stride: c_int,
    subtitle: bool,
}

// Opaque SDK objects/enums not dereferenced here use c_void/c_int respectively.
// MDK_MediaStatus uses all 32 bits (including Invalid = 1<<31).
#[repr(C)]
#[allow(dead_code)]
struct PlayerApi {
    object: *mut c_void,
    set_mute: Option<unsafe extern "C" fn(*mut c_void, bool)>,
    set_volume: Option<unsafe extern "C" fn(*mut c_void, f32)>,
    set_media: Option<unsafe extern "C" fn(*mut c_void, *const c_char)>,
    set_media_for_type: Option<unsafe extern "C" fn(*mut c_void, *const c_char, c_int)>,
    url: Option<unsafe extern "C" fn(*mut c_void) -> *const c_char>,
    set_preload_immediately: Option<unsafe extern "C" fn(*mut c_void, bool)>,
    set_next_media: Option<unsafe extern "C" fn(*mut c_void, *const c_char, i64, c_int)>,
    current_media_changed: Option<unsafe extern "C" fn(*mut c_void, VoidCallback)>,
    set_audio_backends: Option<unsafe extern "C" fn(*mut c_void, *mut *const c_char)>,
    set_audio_decoders: Option<unsafe extern "C" fn(*mut c_void, *mut *const c_char)>,
    set_video_decoders: Option<unsafe extern "C" fn(*mut c_void, *mut *const c_char)>,
    set_timeout: Option<unsafe extern "C" fn(*mut c_void, i64, TimeoutCallback)>,
    prepare: Option<unsafe extern "C" fn(*mut c_void, i64, PrepareCallback, c_int)>,
    media_info: Option<unsafe extern "C" fn(*mut c_void) -> *const c_void>,
    set_state: Option<unsafe extern "C" fn(*mut c_void, c_int)>,
    state: Option<unsafe extern "C" fn(*mut c_void) -> c_int>,
    on_state_changed: Option<unsafe extern "C" fn(*mut c_void, StateCallback)>,
    wait_for: Option<unsafe extern "C" fn(*mut c_void, c_int, c_long) -> bool>,
    media_status: Option<unsafe extern "C" fn(*mut c_void) -> u32>,
    on_media_status_changed: Option<unsafe extern "C" fn(*mut c_void, StatusCallback)>,
    update_native_surface:
        Option<unsafe extern "C" fn(*mut c_void, *mut c_void, c_int, c_int, c_int)>,
    create_surface: Option<unsafe extern "C" fn(*mut c_void, *mut c_void, c_int)>,
    resize_surface: Option<unsafe extern "C" fn(*mut c_void, c_int, c_int)>,
    show_surface: Option<unsafe extern "C" fn(*mut c_void)>,
    get_video_frame: Option<unsafe extern "C" fn(*mut c_void, *mut VideoFrameApi, *mut c_void)>,
    set_video_surface_size: Option<unsafe extern "C" fn(*mut c_void, c_int, c_int, *mut c_void)>,
    set_video_viewport: Option<unsafe extern "C" fn(*mut c_void, f32, f32, f32, f32, *mut c_void)>,
    set_aspect_ratio: Option<unsafe extern "C" fn(*mut c_void, f32, *mut c_void)>,
    rotate: Option<unsafe extern "C" fn(*mut c_void, c_int, *mut c_void)>,
    scale: Option<unsafe extern "C" fn(*mut c_void, f32, f32, *mut c_void)>,
    render_video: Option<unsafe extern "C" fn(*mut c_void, *mut c_void) -> f64>,
    set_background_color:
        Option<unsafe extern "C" fn(*mut c_void, f32, f32, f32, f32, *mut c_void)>,
    set_render_callback: Option<unsafe extern "C" fn(*mut c_void, RenderCallback)>,
    on_video: Option<unsafe extern "C" fn(*mut c_void, VideoCallback)>,
    on_audio: Option<unsafe extern "C" fn(*mut c_void, AudioCallback)>,
    before_video_render: Option<
        unsafe extern "C" fn(
            *mut c_void,
            Option<unsafe extern "C" fn(*mut VideoFrameApi, *mut c_void)>,
        ),
    >,
    after_video_render: Option<
        unsafe extern "C" fn(
            *mut c_void,
            Option<unsafe extern "C" fn(*mut VideoFrameApi, *mut c_void)>,
        ),
    >,
    position: Option<unsafe extern "C" fn(*mut c_void) -> i64>,
    seek_with_flags: Option<unsafe extern "C" fn(*mut c_void, i64, c_int, SeekCallback) -> bool>,
    seek: Option<unsafe extern "C" fn(*mut c_void, i64, SeekCallback) -> bool>,
    set_playback_rate: Option<unsafe extern "C" fn(*mut c_void, f32)>,
    playback_rate: Option<unsafe extern "C" fn(*mut c_void) -> f32>,
    buffered: Option<unsafe extern "C" fn(*mut c_void, *mut i64) -> i64>,
    switch_bitrate: Option<unsafe extern "C" fn(*mut c_void, *const c_char, i64, BitrateCallback)>,
    switch_bitrate_single_connection:
        Option<unsafe extern "C" fn(*mut c_void, *const c_char, BitrateCallback) -> bool>,
    on_event: Option<unsafe extern "C" fn(*mut c_void, EventCallback, *mut u64)>,
    set_buffer_range: Option<unsafe extern "C" fn(*mut c_void, i64, i64, bool)>,
    snapshot: Option<
        unsafe extern "C" fn(*mut c_void, *mut SnapshotRequest, SnapshotCallback, *mut c_void),
    >,
}

#[repr(C)]
#[allow(dead_code)]
struct VideoFrameApi {
    object: *mut c_void,
    plane_count: Option<unsafe extern "C" fn(*mut c_void) -> c_int>,
    width: Option<unsafe extern "C" fn(*mut c_void, c_int) -> c_int>,
    height: Option<unsafe extern "C" fn(*mut c_void, c_int) -> c_int>,
    format: Option<unsafe extern "C" fn(*mut c_void) -> c_int>,
    add_buffer: Option<
        unsafe extern "C" fn(
            *mut c_void,
            *const u8,
            c_int,
            *mut c_void,
            Option<unsafe extern "C" fn(*mut *mut c_void)>,
            c_int,
        ) -> bool,
    >,
    set_buffers: Option<unsafe extern "C" fn(*mut c_void, *const *const u8, *mut c_int)>,
    buffer_data: Option<unsafe extern "C" fn(*mut c_void, c_int) -> *const u8>,
    bytes_per_line: Option<unsafe extern "C" fn(*mut c_void, c_int) -> c_int>,
    set_timestamp: Option<unsafe extern "C" fn(*mut c_void, f64)>,
    timestamp: Option<unsafe extern "C" fn(*mut c_void) -> f64>,
}

#[derive(Clone)]
struct Decoded {
    pts: f64,
    elapsed_us: u64,
    track: i32,
}

#[derive(Clone)]
struct SnapshotMetadata {
    request: u64,
    pts: f64,
    elapsed_us: u64,
    width: i32,
    height: i32,
}

enum SnapshotState {
    Pending,
    Ready(Vec<u8>),
    Failed,
}

struct TraceState {
    decoded: VecDeque<Decoded>,
    request: Option<(u64, SnapshotState)>,
    latest_snapshot: Option<SnapshotMetadata>,
}

struct Trace {
    player: u64,
    start_us: u64,
    closed: AtomicBool,
    drops: AtomicU64,
    state: Mutex<TraceState>,
}

impl Trace {
    fn elapsed_us(&self) -> u64 {
        interop_core::media::monotonic_micros().saturating_sub(self.start_us)
    }
}

#[derive(Clone)]
struct Request {
    trace: Arc<Trace>,
    width: i32,
    height: i32,
    submitted: Instant,
}

#[derive(Default)]
struct Registry {
    traces: HashMap<u64, Arc<Trace>>,
    requests: HashMap<u64, Request>,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);
static REGISTRY_DROPS: AtomicU64 = AtomicU64::new(0);

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| Mutex::new(Registry::default()))
}

fn next_token() -> Option<u64> {
    let mut token = NEXT_TOKEN.load(Ordering::Relaxed);
    loop {
        let next = token
            .checked_add(1)
            .filter(|next| *next <= usize::MAX as u64)?;
        match NEXT_TOKEN.compare_exchange_weak(token, next, Ordering::Relaxed, Ordering::Relaxed) {
            Ok(_) => return Some(token),
            Err(current) => token = current,
        }
    }
}

fn get_trace(token: u64) -> Option<Arc<Trace>> {
    registry().lock().ok()?.traces.get(&token).cloned()
}

fn valid_pts(pts: f64) -> bool {
    pts.is_finite() && (0.0..f64::MAX).contains(&pts)
}

unsafe extern "C" fn video_callback(
    frame: *mut *mut VideoFrameApi,
    track: c_int,
    opaque: *mut c_void,
) -> c_int {
    let trace = {
        let Ok(registry) = registry().try_lock() else {
            REGISTRY_DROPS.fetch_add(1, Ordering::Relaxed);
            return 0;
        };
        registry.traces.get(&(opaque as usize as u64)).cloned()
    };
    let Some(trace) = trace else {
        return 0;
    };
    if trace.closed.load(Ordering::Acquire) || frame.is_null() {
        return 0;
    }
    let elapsed_us = trace.elapsed_us();
    // SAFETY: MDK lends this in/out frame only for this callback invocation.
    // We never replace the pointer, retain its object, or read image buffers.
    let Some(frame) = (unsafe { (*frame).as_ref() }) else {
        return 0;
    };
    let Some(timestamp) = frame.timestamp else {
        return 0;
    };
    if frame.object.is_null() {
        return 0;
    }
    let pts = unsafe { timestamp(frame.object) };
    if !valid_pts(pts) || trace.closed.load(Ordering::Acquire) {
        return 0;
    }
    let Ok(mut state) = trace.state.try_lock() else {
        trace.drops.fetch_add(1, Ordering::Relaxed);
        return 0;
    };
    if state.decoded.len() == MAX_DECODED {
        state.decoded.pop_front();
        trace.drops.fetch_add(1, Ordering::Relaxed);
    }
    state.decoded.push_back(Decoded {
        pts,
        elapsed_us,
        track,
    });
    0
}

unsafe extern "C" fn snapshot_callback(
    result: *mut SnapshotRequest,
    pts: f64,
    opaque: *mut c_void,
) -> *mut c_char {
    let request_id = opaque as usize as u64;
    let request = {
        // A snapshot is a request/response, not a droppable frame metric. MDK
        // invokes it on a dedicated thread; short registry/state locks ensure
        // a concurrent Dart poll cannot discard its only completion.
        let Ok(registry) = registry().lock() else {
            return ptr::null_mut();
        };
        registry.requests.get(&request_id).cloned()
    };
    let Some(request) = request else {
        return ptr::null_mut();
    };
    if request.trace.closed.load(Ordering::Acquire) {
        return ptr::null_mut();
    }
    let elapsed_us = request.trace.elapsed_us();
    // MDK owns the request and pixels until this callback returns. Copy only
    // validated rows. Preserve MDK's native 4-channel order, just as fvp does;
    // the SDK describes data as rgba OR bgra and supplies no format tag here.
    let pixels = unsafe { copy_snapshot(result, &request, pts) };
    let Ok(mut state) = request.trace.state.lock() else {
        return ptr::null_mut();
    };
    if request.trace.closed.load(Ordering::Acquire) {
        return ptr::null_mut();
    }
    if let Some((id, status @ SnapshotState::Pending)) = &mut state.request
        && *id == request_id
    {
        match pixels {
            Some(pixels) => {
                *status = SnapshotState::Ready(pixels);
                state.latest_snapshot = Some(SnapshotMetadata {
                    request: request_id,
                    pts,
                    elapsed_us,
                    width: request.width,
                    height: request.height,
                });
            }
            None => *status = SnapshotState::Failed,
        }
    }
    ptr::null_mut() // Never ask MDK to save an image or free a Rust allocation.
}

unsafe fn copy_snapshot(
    result: *mut SnapshotRequest,
    request: &Request,
    pts: f64,
) -> Option<Vec<u8>> {
    let result = unsafe { result.as_ref() }?;
    if !valid_pts(pts)
        || result.data.is_null()
        || result.width != request.width
        || result.height != request.height
        || result.stride <= 0
    {
        return None;
    }
    let row = usize::try_from(result.width).ok()?.checked_mul(4)?;
    let stride = usize::try_from(result.stride).ok()?;
    let height = usize::try_from(result.height).ok()?;
    let length = row.checked_mul(height)?;
    let source_length = stride.checked_mul(height)?;
    if stride < row
        || stride > MAX_SIDE as usize * 4
        || source_length > MAX_SNAPSHOT_BYTES
        || length > MAX_SNAPSHOT_BYTES
    {
        return None;
    }
    let mut pixels = vec![0; length];
    for y in 0..height {
        // SAFETY: the SDK promises stride*height bytes for a successful result.
        // Bounds above cap both source span and tightly packed output.
        unsafe {
            ptr::copy_nonoverlapping(
                result.data.add(y * stride),
                pixels.as_mut_ptr().add(y * row),
                row,
            )
        };
    }
    Some(pixels)
}

/// Returns zero for unsupported MDK version, duplicate owner, or capacity limit.
/// # Safety
/// `player` must satisfy this module's live, app-owned MDK handle contract.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trace_open(player: u64, mdk_version: i32) -> u64 {
    // MDK_VERSION_INT(0,39,patch), per c/global.h. Reject before dereferencing.
    if mdk_version & !0xff != 0x2700
        || player == 0
        || usize::try_from(player).is_err()
        || !player.is_multiple_of(std::mem::align_of::<PlayerApi>() as u64)
    {
        return 0;
    }
    let api = unsafe { &*(player as usize as *const PlayerApi) };
    let Some(on_video) = api.on_video else {
        return 0;
    };
    if api.object.is_null() || api.snapshot.is_none() {
        return 0;
    }
    let Some(token) = next_token() else {
        return 0;
    };
    {
        let Ok(mut registry) = registry().lock() else {
            return 0;
        };
        if registry.traces.len() >= MAX_TRACES
            || registry.traces.values().any(|trace| trace.player == player)
        {
            return 0;
        }
        registry.traces.insert(
            token,
            Arc::new(Trace {
                player,
                start_us: interop_core::media::monotonic_micros(),
                closed: AtomicBool::new(false),
                drops: AtomicU64::new(0),
                state: Mutex::new(TraceState {
                    decoded: VecDeque::with_capacity(MAX_DECODED),
                    request: None,
                    latest_snapshot: None,
                }),
            }),
        );
    }
    // SAFETY: caller owns the live handle; no Rust lock is held. Do not construct
    // mdk::Player: even its non-owning destructor resets existing fvp callbacks.
    unsafe {
        on_video(
            api.object,
            VideoCallback {
                cb: Some(video_callback),
                opaque: token as usize as *mut c_void,
            },
        )
    };
    token
}

/// Revokes this generation only; intentionally performs no MDK call.
#[unsafe(no_mangle)]
pub extern "C" fn trace_close(player: u64, token: u64) {
    let Ok(mut registry) = registry().lock() else {
        return;
    };
    if !registry
        .traces
        .get(&token)
        .is_some_and(|trace| trace.player == player)
    {
        return;
    }
    if let Some(trace) = registry.traces.remove(&token) {
        trace.closed.store(true, Ordering::Release);
        registry
            .requests
            .retain(|_, request| !Arc::ptr_eq(&request.trace, &trace));
    }
}

/// One outstanding request per trace; dimensions must both be in 1..=256.
/// # Safety
/// `player` and `vo` must be live app-owned MDK handles, with calls serialized
/// against close/dispose. MDK copies this request during snapshot(), as in fvp.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trace_snapshot(
    player: u64,
    token: u64,
    vo: u64,
    width: i32,
    height: i32,
) -> u64 {
    if !(1..=MAX_SIDE).contains(&width)
        || !(1..=MAX_SIDE).contains(&height)
        || usize::try_from(vo).is_err()
    {
        return 0;
    }
    let Some(trace) = get_trace(token) else {
        return 0;
    };
    if trace.player != player || trace.closed.load(Ordering::Acquire) {
        return 0;
    }
    let Some(request_id) = next_token() else {
        return 0;
    };
    {
        let Ok(mut state) = trace.state.lock() else {
            return 0;
        };
        if state.request.is_some() {
            return 0;
        }
        state.request = Some((request_id, SnapshotState::Pending));
    }
    {
        let Ok(mut registry) = registry().lock() else {
            return 0;
        };
        registry.requests.insert(
            request_id,
            Request {
                trace: trace.clone(),
                width,
                height,
                submitted: Instant::now(),
            },
        );
    }
    let api = unsafe { &*(player as usize as *const PlayerApi) };
    let mut request = SnapshotRequest {
        data: ptr::null_mut(),
        width,
        height,
        stride: 0,
        subtitle: false,
    };
    // Same borrowed-handle/stack request usage as fvp MdkSnapshot. No caller
    // image buffer is supplied, so MDK owns the image until callback returns.
    if let Some(snapshot) = api.snapshot {
        unsafe {
            snapshot(
                api.object,
                &mut request,
                SnapshotCallback {
                    cb: Some(snapshot_callback),
                    opaque: request_id as usize as *mut c_void,
                },
                vo as usize as *mut c_void,
            )
        };
    }
    request_id
}

/// 0=pending, >0=tightly packed native RGBA/BGRA byte count; consumes on success.
/// -1=closed/unknown/consumed, -2=failed, -3=capacity, -4=pending beyond 5s.
/// -4 is nonterminal: a caller timeout cannot cancel an MDK snapshot. Keep its
/// admission and callback token until actual completion or explicit trace close.
/// A capacity error preserves the result for a subsequent sufficiently sized poll.
/// # Safety
/// `out` must be writable for `capacity` bytes when a result is copied.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trace_poll(token: u64, request: u64, out: *mut u8, capacity: u32) -> i32 {
    let Some(trace) = get_trace(token) else {
        return CLOSED;
    };
    let submitted = {
        let Ok(registry) = registry().lock() else {
            return FAILED;
        };
        let Some(entry) = registry.requests.get(&request) else {
            return CLOSED;
        };
        if !Arc::ptr_eq(&entry.trace, &trace) {
            return CLOSED;
        }
        entry.submitted
    };
    let result = {
        let Ok(state) = trace.state.lock() else {
            return FAILED;
        };
        let Some((id, status)) = &state.request else {
            return CLOSED;
        };
        if *id != request {
            return CLOSED;
        }
        match status {
            SnapshotState::Pending if submitted.elapsed() < SNAPSHOT_TIMEOUT => return 0,
            SnapshotState::Pending => return TIMED_OUT,
            SnapshotState::Failed => FAILED,
            SnapshotState::Ready(pixels) => {
                if out.is_null() || (capacity as usize) < pixels.len() {
                    return CAPACITY;
                }
                unsafe { ptr::copy_nonoverlapping(pixels.as_ptr(), out, pixels.len()) };
                pixels.len() as i32
            }
        }
    };
    // Take/drop the image outside callbacks. Do not hold state and registry locks
    // together, and do not let an old request consume a newer request.
    if let Ok(mut state) = trace.state.lock()
        && state.request.as_ref().is_some_and(|(id, _)| *id == request)
    {
        state.request = None;
    }
    if let Ok(mut registry) = registry().lock() {
        registry.requests.remove(&request);
    }
    result
}

/// Copies bounded UTF-8 JSON, without NUL or image bytes. Recent decoded frames
/// remain available across reads. nowElapsedUs, frame and snapshot elapsedUs all
/// share this trace's Instant. registryDrops is process-wide lock contention.
/// # Safety
/// `out` must be writable for `capacity` bytes when JSON is copied.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trace_metrics(token: u64, out: *mut u8, capacity: u32) -> i32 {
    let Some(trace) = get_trace(token) else {
        return CLOSED;
    };
    let (decoded, snapshot) = {
        let Ok(state) = trace.state.lock() else {
            return FAILED;
        };
        (
            state.decoded.iter().cloned().collect::<Vec<_>>(),
            state.latest_snapshot.clone(),
        )
    };
    let decoded: Vec<_> = decoded
        .into_iter()
        .map(|frame| {
            serde_json::json!({
                "ptsSeconds": frame.pts, "elapsedUs": frame.elapsed_us, "track": frame.track,
            })
        })
        .collect();
    let snapshot = snapshot.map(|frame| {
        serde_json::json!({
            "requestId": frame.request, "ptsSeconds": frame.pts, "elapsedUs": frame.elapsed_us,
            "width": frame.width, "height": frame.height,
        })
    });
    let value = serde_json::json!({
        "clockOriginUs": trace.start_us,
        "nowElapsedUs": trace.elapsed_us(), "decoded": decoded, "snapshot": snapshot,
        "drops": trace.drops.load(Ordering::Relaxed),
        "registryDrops": REGISTRY_DROPS.load(Ordering::Relaxed),
        "pixelFormat": "mdk-native-4",
    });
    let Ok(json) = serde_json::to_vec(&value) else {
        return FAILED;
    };
    if json.len() > MAX_METRICS_BYTES || (capacity as usize) < json.len() || out.is_null() {
        return CAPACITY;
    }
    unsafe { ptr::copy_nonoverlapping(json.as_ptr(), out, json.len()) };
    json.len() as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Barrier;

    // Exact loss counts must not contend with unrelated parallel test traces.
    static TEST_SERIAL: Mutex<()> = Mutex::new(());

    #[derive(Default)]
    struct FakePlayer {
        video: Mutex<Option<VideoCallback>>,
        snapshots: Mutex<Vec<SnapshotCallback>>,
    }

    unsafe extern "C" fn register_video(object: *mut c_void, callback: VideoCallback) {
        // SAFETY: the fixture keeps its boxed FakePlayer alive through registration.
        let player = unsafe { &*(object.cast::<FakePlayer>()) };
        *player.video.lock().unwrap() = Some(callback);
    }

    unsafe extern "C" fn request_snapshot(
        object: *mut c_void,
        request: *mut SnapshotRequest,
        callback: SnapshotCallback,
        _vo: *mut c_void,
    ) {
        let player = unsafe { &*(object.cast::<FakePlayer>()) };
        let request = unsafe { &*request };
        assert!(request.data.is_null());
        assert!((1..=256).contains(&request.width));
        assert!((1..=256).contains(&request.height));
        player.snapshots.lock().unwrap().push(callback);
    }

    struct Fixture {
        _serial: std::sync::MutexGuard<'static, ()>,
        player: Box<FakePlayer>,
        api: Box<PlayerApi>,
        token: u64,
    }

    impl Fixture {
        fn new() -> Self {
            let serial = TEST_SERIAL
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            let mut player = Box::<FakePlayer>::default();
            // All fields are nullable C function pointers/raw pointers.
            let mut api: Box<PlayerApi> = Box::new(unsafe { std::mem::zeroed() });
            api.object = (&mut *player as *mut FakePlayer).cast();
            api.on_video = Some(register_video);
            api.snapshot = Some(request_snapshot);
            let token = unsafe { trace_open((&*api as *const PlayerApi) as u64, 0x2700) };
            assert_ne!(token, 0);
            Self {
                _serial: serial,
                player,
                api,
                token,
            }
        }

        fn handle(&self) -> u64 {
            (&*self.api as *const PlayerApi) as u64
        }

        fn callback(&self) -> VideoCallback {
            self.player.video.lock().unwrap().unwrap()
        }

        fn metrics(&self) -> serde_json::Value {
            let mut buffer = vec![0; MAX_METRICS_BYTES];
            let length =
                unsafe { trace_metrics(self.token, buffer.as_mut_ptr(), buffer.len() as u32) };
            assert!(length > 0);
            serde_json::from_slice(&buffer[..length as usize]).unwrap()
        }

        fn snapshot(&self, width: i32, height: i32) -> (u64, SnapshotCallback) {
            let request = unsafe { trace_snapshot(self.handle(), self.token, 0, width, height) };
            assert_ne!(request, 0);
            let callback = *self.player.snapshots.lock().unwrap().last().unwrap();
            (request, callback)
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            trace_close(self.handle(), self.token);
        }
    }

    struct Frame {
        pts: f64,
        entered: Option<Arc<Barrier>>,
        release: Option<Arc<Barrier>>,
    }

    unsafe extern "C" fn timestamp(object: *mut c_void) -> f64 {
        let frame = unsafe { &*object.cast::<Frame>() };
        if let Some(barrier) = &frame.entered {
            barrier.wait();
        }
        if let Some(barrier) = &frame.release {
            barrier.wait();
        }
        frame.pts
    }

    fn emit(callback: VideoCallback, frame: &mut Frame, track: i32) {
        let mut api: VideoFrameApi = unsafe { std::mem::zeroed() };
        api.object = (frame as *mut Frame).cast();
        api.timestamp = Some(timestamp);
        let original = &mut api as *mut VideoFrameApi;
        let mut pointer = original;
        let result = unsafe { callback.cb.unwrap()(&mut pointer, track, callback.opaque) };
        assert_eq!(result, 0);
        assert_eq!(
            pointer, original,
            "observer must pass the original frame through"
        );
    }

    #[test]
    fn registered_callback_records_bounded_frames_and_close_rejects_late_frames() {
        let fixture = Fixture::new();
        let callback = fixture.callback();
        let mut frame = Frame {
            pts: 1.25,
            entered: None,
            release: None,
        };
        for _ in 0..300 {
            emit(callback, &mut frame, 2);
        }
        let metrics = fixture.metrics();
        assert_eq!(metrics["decoded"].as_array().unwrap().len(), 256);
        assert_eq!(metrics["drops"], 44);
        assert_eq!(metrics["decoded"][255]["ptsSeconds"], 1.25);
        assert_eq!(metrics["decoded"][255]["track"], 2);
        assert!(
            metrics["nowElapsedUs"].as_u64().unwrap()
                >= metrics["decoded"][255]["elapsedUs"].as_u64().unwrap()
        );
        trace_close(fixture.handle(), fixture.token);
        // A retired generation must return before touching even the frame argument.
        let result = unsafe { callback.cb.unwrap()(std::ptr::dangling_mut(), 0, callback.opaque) };
        assert_eq!(result, 0);
        assert_eq!(
            unsafe { trace_metrics(fixture.token, std::ptr::null_mut(), 0) },
            CLOSED
        );
    }

    #[test]
    fn close_during_native_timestamp_read_does_not_wait_or_retain_frame() {
        let fixture = Fixture::new();
        let callback = fixture.callback();
        let function = callback.cb.unwrap();
        let opaque = callback.opaque as usize;
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let worker_entered = entered.clone();
        let worker_release = release.clone();
        let worker = std::thread::spawn(move || {
            let mut frame = Frame {
                pts: 3.0,
                entered: Some(worker_entered),
                release: Some(worker_release),
            };
            emit(
                VideoCallback {
                    cb: Some(function),
                    opaque: opaque as *mut c_void,
                },
                &mut frame,
                0,
            );
        });
        entered.wait();
        trace_close(fixture.handle(), fixture.token);
        assert_eq!(
            unsafe { trace_metrics(fixture.token, std::ptr::null_mut(), 0) },
            CLOSED
        );
        release.wait();
        worker.join().unwrap();
    }

    #[test]
    fn snapshot_poll_copies_rows_and_retains_matching_timestamp_without_pixels_in_json() {
        let fixture = Fixture::new();
        let (request, callback) = fixture.snapshot(1, 2);
        let mut pixels = [
            1_u8, 2, 3, 255, 90, 90, 90, 90, 4, 5, 6, 255, 91, 91, 91, 91,
        ];
        let mut result = SnapshotRequest {
            data: pixels.as_mut_ptr(),
            width: 1,
            height: 2,
            stride: 8,
            subtitle: false,
        };
        assert!(unsafe { callback.cb.unwrap()(&mut result, 4.5, callback.opaque) }.is_null());
        pixels.fill(0); // Native image memory may be destroyed immediately after callback.
        let mut output = [0_u8; 8];
        assert_eq!(
            unsafe { trace_poll(fixture.token, request, output.as_mut_ptr(), 7) },
            CAPACITY
        );
        assert_eq!(
            unsafe { trace_poll(fixture.token, request, output.as_mut_ptr(), 8) },
            8
        );
        assert_eq!(output, [1, 2, 3, 255, 4, 5, 6, 255]);
        let metrics = fixture.metrics();
        assert_eq!(metrics["snapshot"]["requestId"], request);
        assert_eq!(metrics["snapshot"]["ptsSeconds"], 4.5);
        assert_eq!(metrics["snapshot"]["width"], 1);
        assert_eq!(metrics["snapshot"]["height"], 2);
        assert!(
            metrics["nowElapsedUs"].as_u64().unwrap()
                >= metrics["snapshot"]["elapsedUs"].as_u64().unwrap()
        );
        assert!(metrics["snapshot"].get("pixels").is_none());
        assert_eq!(
            unsafe { trace_poll(fixture.token, request, output.as_mut_ptr(), 8) },
            CLOSED
        );
    }

    #[test]
    fn snapshot_failure_and_invalid_stride_are_reclaimable_and_late_results_are_ignored() {
        let fixture = Fixture::new();
        let (first, callback) = fixture.snapshot(2, 2);
        assert_eq!(
            unsafe { trace_poll(fixture.token, first, std::ptr::null_mut(), 0) },
            0
        );
        unsafe { callback.cb.unwrap()(std::ptr::null_mut(), 0.0, callback.opaque) };
        assert_eq!(
            unsafe { trace_poll(fixture.token, first, std::ptr::null_mut(), 0) },
            FAILED
        );
        let (second, second_callback) = fixture.snapshot(2, 2);
        assert_ne!(first, second);
        let mut result = SnapshotRequest {
            data: std::ptr::dangling_mut(),
            width: 2,
            height: 2,
            stride: 7,
            subtitle: false,
        };
        unsafe { second_callback.cb.unwrap()(&mut result, 1.0, second_callback.opaque) };
        assert_eq!(
            unsafe { trace_poll(fixture.token, second, std::ptr::null_mut(), 0) },
            FAILED
        );
        let (_third, third_callback) = fixture.snapshot(2, 2);
        trace_close(fixture.handle(), fixture.token);
        // Callback cannot dereference this result after close revoked the request token.
        unsafe { third_callback.cb.unwrap()(std::ptr::dangling_mut(), 1.0, third_callback.opaque) };
    }

    #[test]
    fn wrong_owner_version_and_oversize_requests_do_not_reach_mdk() {
        let fixture = Fixture::new();
        assert_eq!(unsafe { trace_open(1, 0x2600) }, 0); // Version is checked before pointer access.
        assert_eq!(unsafe { trace_open(fixture.handle(), 0x2700) }, 0);
        for (width, height) in [(0, 1), (257, 1), (1, -1), (256, 257)] {
            assert_eq!(
                unsafe { trace_snapshot(fixture.handle(), fixture.token, 0, width, height) },
                0
            );
        }
        assert_eq!(unsafe { trace_snapshot(1, fixture.token, 0, 1, 1) }, 0);
        trace_close(1, fixture.token);
        assert!(fixture.metrics().get("nowElapsedUs").is_some());
        assert!(fixture.player.snapshots.lock().unwrap().is_empty());
    }

    #[test]
    fn timed_out_snapshot_keeps_native_admission_until_actual_callback() {
        let fixture = Fixture::new();
        let (old, late) = fixture.snapshot(2, 2);
        registry()
            .lock()
            .unwrap()
            .requests
            .get_mut(&old)
            .unwrap()
            .submitted = Instant::now() - SNAPSHOT_TIMEOUT;
        let mut out = [0; 16];
        for _ in 0..2 {
            assert_eq!(
                unsafe { trace_poll(fixture.token, old, out.as_mut_ptr(), 16) },
                TIMED_OUT
            );
            assert_eq!(
                unsafe { trace_snapshot(fixture.handle(), fixture.token, 0, 2, 2) },
                0,
                "Caller timeout cannot cancel MDK's pending snapshot"
            );
        }
        assert_eq!(fixture.player.snapshots.lock().unwrap().len(), 1);
        let mut pixels = [42u8; 16];
        let mut result = SnapshotRequest {
            data: pixels.as_mut_ptr(),
            width: 2,
            height: 2,
            stride: 8,
            subtitle: false,
        };
        unsafe { late.cb.unwrap()(&mut result, 1.0, late.opaque) };
        assert_eq!(
            unsafe { trace_poll(fixture.token, old, out.as_mut_ptr(), 16) },
            16
        );
        assert_eq!(out, pixels);
        let (new, fresh) = fixture.snapshot(2, 2);
        assert_ne!(old, new);
        unsafe { fresh.cb.unwrap()(&mut result, 2.0, fresh.opaque) };
        assert_eq!(
            unsafe { trace_poll(fixture.token, new, out.as_mut_ptr(), 16) },
            16
        );
        assert_eq!(fixture.metrics()["snapshot"]["requestId"], new);
        assert_eq!(fixture.metrics()["snapshot"]["ptsSeconds"], 2.0);
    }

    #[test]
    fn sdk_header_prefix_layout_matches_independently_checked_c_layout() {
        // Independently compiled from the installed C SDK headers on x64:
        // onVideo=272, snapshot=384, timestamp=80, sizeof(SnapshotRequest)=24.
        let pointer = std::mem::size_of::<*mut c_void>();
        assert_eq!(std::mem::offset_of!(PlayerApi, on_video), 34 * pointer);
        assert_eq!(std::mem::offset_of!(PlayerApi, snapshot), 48 * pointer);
        assert_eq!(std::mem::offset_of!(VideoFrameApi, timestamp), 10 * pointer);
        if pointer == 8 {
            assert_eq!(std::mem::size_of::<SnapshotRequest>(), 24);
        }
    }

    #[test]
    fn stale_close_and_frame_cannot_affect_reopened_generation() {
        let mut fixture = Fixture::new();
        let old_token = fixture.token;
        let callback = fixture.callback();
        trace_close(fixture.handle(), old_token);
        fixture.token = unsafe { trace_open(fixture.handle(), 0x2700) };
        assert_ne!(fixture.token, 0);
        assert_ne!(fixture.token, old_token);
        trace_close(fixture.handle(), old_token);
        unsafe { callback.cb.unwrap()(std::ptr::dangling_mut(), 0, callback.opaque) };
        assert_eq!(fixture.metrics()["decoded"].as_array().unwrap().len(), 0);
        let mut frame = Frame {
            pts: 9.0,
            entered: None,
            release: None,
        };
        emit(fixture.callback(), &mut frame, 1);
        assert_eq!(fixture.metrics()["decoded"][0]["ptsSeconds"], 9.0);
    }

    fn contended_snapshot_worker(
        callback: SnapshotCallback,
    ) -> (
        std::thread::JoinHandle<()>,
        std::sync::mpsc::Receiver<()>,
        Arc<Barrier>,
    ) {
        let function = callback.cb.unwrap();
        let opaque = callback.opaque as usize;
        let entered = Arc::new(Barrier::new(2));
        let worker_entered = entered.clone();
        let (sent, received) = std::sync::mpsc::channel();
        let worker = std::thread::spawn(move || {
            let mut pixels = [10_u8, 20, 30, 255];
            let mut result = SnapshotRequest {
                data: pixels.as_mut_ptr(),
                width: 1,
                height: 1,
                stride: 4,
                subtitle: false,
            };
            worker_entered.wait();
            unsafe { function(&mut result, 12.0, opaque as *mut c_void) };
            sent.send(()).unwrap();
        });
        (worker, received, entered)
    }

    #[test]
    fn snapshot_response_survives_real_registry_and_poll_state_contention() {
        let fixture = Fixture::new();
        let mut pixels = [0_u8; 4];
        for registry_contention in [true, false] {
            let (request, callback) = fixture.snapshot(1, 1);
            let trace = get_trace(fixture.token).unwrap();
            // Hold the same actual locks taken briefly by exports. The callback
            // must wait for their release, rather than abandon its only result.
            let registry_guard = registry_contention.then(|| registry().lock().unwrap());
            let state_guard = (!registry_contention).then(|| trace.state.lock().unwrap());
            let (worker, completed, entered) = contended_snapshot_worker(callback);
            entered.wait();
            assert!(matches!(
                completed.recv_timeout(Duration::from_millis(50)),
                Err(std::sync::mpsc::RecvTimeoutError::Timeout)
            ));
            drop(state_guard);
            drop(registry_guard);
            completed.recv_timeout(Duration::from_secs(1)).unwrap();
            worker.join().unwrap();
            assert_eq!(
                unsafe { trace_poll(fixture.token, request, pixels.as_mut_ptr(), 4) },
                4
            );
            assert_eq!(pixels, [10, 20, 30, 255]);
        }
    }
}
