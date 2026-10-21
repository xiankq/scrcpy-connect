//! Atomic application admission, independent of unknown device codec capacity.
//!
//! A reservation covers startup and teardown as well as active presentation.
//! Dropping it releases only its own activity; admission never evicts anything.
use crate::CoreError;
use serde::Serialize;
use serde_json::json;
use std::{
    collections::BTreeMap,
    num::NonZeroUsize,
    sync::{Arc, Mutex, MutexGuard},
};
use tokio_util::sync::CancellationToken;

/// An application guard, not a claim that hardware supports sixteen encoders.
pub const APP_SESSION_LIMIT: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceStatus {
    Starting,
    Streaming,
    Paused,
    Stopping,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReservedActivity {
    pub id: String,
    pub device_id: String,
    pub name: String,
    pub status: ResourceStatus,
    pub can_pause: bool,
    pub can_resume: bool,
    pub reserved: bool,
    pub preserved: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BusyReason {
    AppSessionGuard,
    ActivityAlreadyReserved,
    ReplacementUnavailable,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceBusy {
    pub reason: BusyReason,
    pub limit: usize,
    pub activities: Vec<ReservedActivity>,
    pub hardware_capacity_known: bool,
    pub existing_activities_preserved: bool,
    pub pause_releases_reservation: bool,
}

impl From<ResourceBusy> for CoreError {
    fn from(busy: ResourceBusy) -> Self {
        let mut error = CoreError::new(
            "resource_busy",
            "当前活动已达到应用保护上限；已有活动保持不变。可查看当前活动，明确关闭一个画面后再重试。",
        );
        error.details = json!(busy);
        error
    }
}

struct Entry {
    activity: ReservedActivity,
    cancellation: CancellationToken,
}
struct State {
    entries: BTreeMap<String, Entry>,
    limit: usize,
    replacement: Option<(String, String)>,
}

#[derive(Clone)]
pub struct ResourceAdmission {
    state: Arc<Mutex<State>>,
}

impl Default for ResourceAdmission {
    fn default() -> Self {
        Self::new(NonZeroUsize::new(APP_SESSION_LIMIT).expect("positive guard"))
    }
}

impl ResourceAdmission {
    pub fn new(limit: NonZeroUsize) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                entries: BTreeMap::new(),
                limit: limit.get(),
                replacement: None,
            })),
        }
    }

    fn state(&self) -> MutexGuard<'_, State> {
        // No callbacks, awaits, or fallible user code execute while holding it.
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
    }

    /// Checks and inserts under one lock, before any asynchronous allocation.
    /// The caller keeps the returned guard until its teardown has finished.
    pub fn reserve_session(
        &self,
        id: String,
        device_id: String,
        name: String,
        cancellation: CancellationToken,
    ) -> Result<ResourceReservation, ResourceBusy> {
        self.reserve(id, device_id, name, cancellation, None)
    }

    /// One transient capture may coexist with its exact same-device source.
    /// Only the quality executor uses this seam while holding quality_changes;
    /// the admission lock independently bounds all replacements to one extra.
    pub(crate) fn reserve_replacement(
        &self,
        previous_id: &str,
        id: String,
        device_id: String,
        name: String,
        cancellation: CancellationToken,
    ) -> Result<ResourceReservation, ResourceBusy> {
        self.reserve(id, device_id, name, cancellation, Some(previous_id))
    }

    fn reserve(
        &self,
        id: String,
        device_id: String,
        name: String,
        cancellation: CancellationToken,
        previous_id: Option<&str>,
    ) -> Result<ResourceReservation, ResourceBusy> {
        let mut state = self.state();
        let reason = if state.entries.contains_key(&id) {
            Some(BusyReason::ActivityAlreadyReserved)
        } else if let Some(previous_id) = previous_id {
            if state.replacement.is_some()
                || state.entries.len() > state.limit
                || state
                    .entries
                    .get(previous_id)
                    .is_none_or(|entry| entry.activity.device_id != device_id)
            {
                Some(BusyReason::ReplacementUnavailable)
            } else {
                None
            }
        } else if state.entries.len() >= state.limit {
            Some(BusyReason::AppSessionGuard)
        } else {
            None
        };
        if let Some(reason) = reason {
            return Err(ResourceBusy {
                reason,
                limit: state.limit,
                activities: state
                    .entries
                    .values()
                    .map(|entry| entry.activity.clone())
                    .collect(),
                hardware_capacity_known: false,
                existing_activities_preserved: true,
                pause_releases_reservation: false,
            });
        }
        if let Some(previous_id) = previous_id {
            state.replacement = Some((previous_id.to_owned(), id.clone()));
        }
        state.entries.insert(
            id.clone(),
            Entry {
                activity: ReservedActivity {
                    id: id.clone(),
                    device_id,
                    name,
                    status: ResourceStatus::Starting,
                    can_pause: false,
                    can_resume: false,
                    reserved: true,
                    preserved: true,
                },
                cancellation,
            },
        );
        Ok(ResourceReservation {
            admission: self.clone(),
            id,
        })
    }

    pub fn activities(&self) -> Vec<ReservedActivity> {
        self.state()
            .entries
            .values()
            .map(|entry| entry.activity.clone())
            .collect()
    }

    pub fn set_status(&self, id: &str, status: ResourceStatus) {
        if let Some(entry) = self.state().entries.get_mut(id) {
            // A late renderer receipt cannot revive a cancelled reservation.
            if entry.cancellation.is_cancelled() {
                return;
            }
            entry.activity.status = status;
            entry.activity.can_pause = status == ResourceStatus::Streaming;
            entry.activity.can_resume = status == ResourceStatus::Paused;
        }
    }

    /// Explicit user cancellation; capacity stays reserved during teardown.
    pub fn cancel(&self, id: &str) -> bool {
        let mut state = self.state();
        if let Some(entry) = state.entries.get_mut(id) {
            cancel(entry);
            true
        } else {
            false
        }
    }

    pub fn cancel_device(&self, device_id: &str) {
        for entry in self
            .state()
            .entries
            .values_mut()
            .filter(|entry| entry.activity.device_id == device_id)
        {
            cancel(entry);
        }
    }
}

fn cancel(entry: &mut Entry) {
    entry.activity.status = ResourceStatus::Stopping;
    entry.activity.can_pause = false;
    entry.activity.can_resume = false;
    entry.cancellation.cancel();
}

/// Not Clone: there is exactly one teardown owner for each reserved activity.
pub struct ResourceReservation {
    admission: ResourceAdmission,
    id: String,
}

impl ResourceReservation {
    pub fn stopping(&self) {
        if let Some(entry) = self.admission.state().entries.get_mut(&self.id) {
            cancel(entry);
        }
    }
}

impl Drop for ResourceReservation {
    fn drop(&mut self) {
        let mut state = self.admission.state();
        if state
            .replacement
            .as_ref()
            .is_some_and(|(old, new)| old == &self.id || new == &self.id)
        {
            state.replacement = None;
        }
        let entry = state.entries.remove(&self.id);
        if let Some(entry) = entry {
            entry.cancellation.cancel();
        }
    }
}

/// Native evidence is distinct from scrcpy's untyped exception messages.
/// Android CodecException.ERROR_INSUFFICIENT_RESOURCE = 1100; ERROR_RECLAIMED
/// = 1101 means the codec must be released. Neither is a hardware capacity.
/// https://developer.android.com/reference/android/media/MediaCodec.CodecException
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodecFailure {
    InsufficientResource,
    Reclaimed,
    Unclassified,
}

impl CodecFailure {
    pub fn from_android_error_code(code: i32) -> Self {
        match code {
            1100 => Self::InsufficientResource,
            1101 => Self::Reclaimed,
            _ => Self::Unclassified,
        }
    }

    /// Fixed scrcpy 5.0.1 SurfaceEncoder logs exception class + message, not
    /// CodecException.getErrorCode(); generic failures must not authorize retry.
    /// https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L138
    pub fn from_scrcpy_log(_log: &str) -> Self {
        Self::Unclassified
    }
}

/// Permission for one lower-load attempt of a new, side-effect-free request.
/// Does not restart a process, change codec/encoder, or stop an old activity.
#[derive(Default)]
pub struct NewSessionRetry {
    used: bool,
}

impl NewSessionRetry {
    pub fn claim(
        &mut self,
        failure: CodecFailure,
        application_side_effects_possible: bool,
    ) -> bool {
        if self.used
            || application_side_effects_possible
            || failure != CodecFailure::InsufficientResource
        {
            return false;
        }
        self.used = true;
        true
    }
}

#[cfg(test)]
mod replacement_tests {
    use super::*;
    fn reserve(admission: &ResourceAdmission, id: &str, device: &str) -> ResourceReservation {
        admission
            .reserve_session(
                id.into(),
                device.into(),
                id.into(),
                CancellationToken::new(),
            )
            .unwrap()
    }
    #[test]
    fn full_guard_accepts_exact_replacement_but_keeps_normal_start_limited() {
        let admission = ResourceAdmission::new(NonZeroUsize::new(2).unwrap());
        let first = reserve(&admission, "first", "phone");
        let second = reserve(&admission, "second", "other");
        let replacement = admission
            .reserve_replacement(
                "first",
                "new".into(),
                "phone".into(),
                "phone".into(),
                CancellationToken::new(),
            )
            .unwrap();
        assert_eq!(admission.activities().len(), 3);
        assert!(
            admission
                .reserve_session(
                    "ordinary".into(),
                    "phone".into(),
                    "ordinary".into(),
                    CancellationToken::new()
                )
                .is_err()
        );
        assert!(
            admission
                .reserve_replacement(
                    "second",
                    "extra".into(),
                    "other".into(),
                    "extra".into(),
                    CancellationToken::new()
                )
                .is_err()
        );
        drop(first);
        assert_eq!(admission.activities().len(), 2);
        drop(replacement);
        drop(second);
        assert!(admission.activities().is_empty());
    }
    #[test]
    fn replacement_is_bound_to_device_and_capture_and_failure_releases_peak() {
        let admission = ResourceAdmission::new(NonZeroUsize::new(1).unwrap());
        let _original = reserve(&admission, "old", "phone");
        for (source, device) in [("missing", "phone"), ("old", "other")] {
            assert!(
                admission
                    .reserve_replacement(
                        source,
                        "candidate".into(),
                        device.into(),
                        "candidate".into(),
                        CancellationToken::new()
                    )
                    .is_err()
            );
        }
        let token = CancellationToken::new();
        let candidate = admission
            .reserve_replacement(
                "old",
                "candidate".into(),
                "phone".into(),
                "candidate".into(),
                token.clone(),
            )
            .unwrap();
        admission.cancel("candidate");
        assert!(token.is_cancelled());
        assert_eq!(
            admission.activities().len(),
            2,
            "teardown still owns capacity"
        );
        drop(candidate);
        assert_eq!(admission.activities().len(), 1);
        let retry = admission
            .reserve_replacement(
                "old",
                "retry".into(),
                "phone".into(),
                "retry".into(),
                CancellationToken::new(),
            )
            .unwrap();
        drop(retry);
        assert_eq!(admission.activities().len(), 1);
    }
}
