use crate::Decoder;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
};

type Borrow = Arc<Mutex<Option<usize>>>;
static DECODERS: OnceLock<Mutex<HashMap<u64, Borrow>>> = OnceLock::new();
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub(super) fn registry() -> &'static Mutex<HashMap<u64, Borrow>> {
    DECODERS.get_or_init(Mutex::default)
}

pub(super) fn next_id() -> Option<u64> {
    NEXT_ID
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |id| {
            (id < i64::MAX as u64).then_some(id + 1)
        })
        .ok()
}

pub(super) fn register(id: u64, pointer: *mut Decoder) {
    registry()
        .lock()
        .unwrap()
        .insert(id, Arc::new(Mutex::new(Some(pointer as usize))));
}

pub(super) fn with_decoder<T>(id: u64, operation: impl FnOnce(&Decoder) -> T) -> Result<T, String> {
    let borrow = registry()
        .lock()
        .unwrap()
        .get(&id)
        .cloned()
        .ok_or_else(|| "media output is closed".to_owned())?;
    let guard = borrow.lock().unwrap();
    let pointer = guard.ok_or_else(|| "media output is closed".to_owned())?;
    // The per-output lock covers the entire operation. Platform destruction
    // removes admission and waits for this lock before freeing decoder callbacks.
    let result = operation(unsafe { &*(pointer as *const Decoder) });
    drop(guard);
    Ok(result)
}

pub(super) fn revoke(id: u64) {
    let borrow = registry().lock().unwrap().remove(&id);
    if let Some(borrow) = borrow {
        *borrow.lock().unwrap() = None;
    }
}
