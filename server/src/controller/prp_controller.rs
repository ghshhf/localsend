//! PRP relay bridge.
//!
//! A deliberately small rendezvous endpoint pair used by the Flutter client's
//! `ConnectToRelayAction`:
//!
//! 1. `POST /api/prp/register`  — the device announces itself and its self-check
//!    payload, and receives a `device_id` plus an instruction string.
//! 2. `POST /api/prp/message`   — the device reports its self-check back; the
//!    relay stores it and answers with an echo so the client can prove a real
//!    round trip instead of optimistically assuming one.
//!
//! The relay keeps no message queue and never initiates connections, so its
//! attack surface is two `POST` handlers over an in-memory map with a hard
//! device cap and a lease TTL.

use crate::config::state::{AppState, PrpDevice};
use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Hard ceiling on concurrent registrations. Beyond this the relay answers 503
/// rather than growing unbounded — it is a public endpoint with no auth.
const MAX_DEVICES: usize = 2048;

/// A registration is dropped after this many seconds without traffic.
const LEASE_SECS: u64 = 600;

/// Upper bound on the serialized `self_check` payload a device may report.
const MAX_PAYLOAD_BYTES: usize = 8 * 1024;

/// Upper bound on a stored alias (it is echoed back to the owner only, but the
/// map still holds it for the whole lease).
const MAX_ALIAS_CHARS: usize = 64;

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[derive(Deserialize)]
pub struct RegisterRequest {
    #[serde(default)]
    alias: String,
    /// Opaque self-check document produced by the client. Stored verbatim,
    /// never interpreted by the relay.
    #[serde(default)]
    self_check: serde_json::Value,
}

#[derive(Serialize)]
pub struct RegisterResponse {
    ok: bool,
    device_id: String,
    instruction: String,
    /// Remaining lease in seconds, so the client could refresh before expiry.
    lease_secs: u64,
}

#[derive(Deserialize)]
pub struct MessageRequest {
    device_id: String,
    #[serde(default)]
    content: serde_json::Value,
}

#[derive(Serialize)]
pub struct MessageResponse {
    ok: bool,
    relay_says: String,
    /// Echo of how many messages this device has sent, proving the relay is
    /// tracking the same session the client thinks it is in.
    messages: u32,
}

/// Collapse an arbitrary client-supplied alias into something safe to store and
/// log: trimmed, non-empty, and bounded.
fn sanitize_alias(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return "LocalSend".to_string();
    }
    trimmed.chars().take(MAX_ALIAS_CHARS).collect()
}

/// A lease is live while less than `LEASE_SECS` have passed since last contact.
fn lease_live(last_seen: u64, now: u64) -> bool {
    now.saturating_sub(last_seen) < LEASE_SECS
}

/// `POST /api/prp/register`
pub async fn register(
    State(state): State<AppState>,
    Json(payload): Json<RegisterRequest>,
) -> (StatusCode, Json<RegisterResponse>) {
    let self_check_bytes = serde_json::to_vec(&payload.self_check).map_or(0, |v| v.len());
    if self_check_bytes > MAX_PAYLOAD_BYTES {
        // Returned as a plain tuple, so build the error shape by hand.
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(RegisterResponse {
                ok: false,
                device_id: String::new(),
                instruction: format!("self_check 超过 {MAX_PAYLOAD_BYTES} 字节上限"),
                lease_secs: 0,
            }),
        );
    }

    let alias = sanitize_alias(&payload.alias);

    let now = now_secs();
    let device_id = Uuid::new_v4();

    let mut devices = state.prp_devices.lock().await;

    // Drop expired leases first: this keeps the cap meaningful without a
    // background reaper task.
    devices.retain(|_, d| lease_live(d.last_seen, now));

    if devices.len() >= MAX_DEVICES {
        drop(devices);
        // The client maps non-200 to "relay unreachable", so distinguish this
        // from a routing error in the logs at least.
        tracing::warn!("PRP relay at capacity ({MAX_DEVICES}), rejecting registration");
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(RegisterResponse {
                ok: false,
                device_id: String::new(),
                instruction: "中继已满，请稍后重试".to_string(),
                lease_secs: 0,
            }),
        );
    }

    devices.insert(
        device_id,
        PrpDevice {
            alias: alias.clone(),
            self_check: payload.self_check,
            registered_at: now,
            last_seen: now,
            messages: 0,
        },
    );

    tracing::info!(
        "PRP relay: registered {device_id} as {alias:?} ({} device(s) live)",
        devices.len()
    );

    (
        StatusCode::OK,
        Json(RegisterResponse {
            ok: true,
            device_id: device_id.to_string(),
            instruction: format!(
                "已注册为 {alias}，租约 {} 秒。把自检结果 POST 回 /api/prp/message 完成握手。",
                LEASE_SECS
            ),
            lease_secs: LEASE_SECS,
        }),
    )
}

/// `POST /api/prp/message`
pub async fn message(
    State(state): State<AppState>,
    Json(payload): Json<MessageRequest>,
) -> (StatusCode, Json<MessageResponse>) {
    let Ok(device_id) = Uuid::parse_str(payload.device_id.trim()) else {
        return (
            StatusCode::BAD_REQUEST,
            Json(MessageResponse {
                ok: false,
                relay_says: "device_id 不是合法 UUID".to_string(),
                messages: 0,
            }),
        );
    };

    let content_bytes = serde_json::to_vec(&payload.content).map_or(0, |v| v.len());
    if content_bytes > MAX_PAYLOAD_BYTES {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(MessageResponse {
                ok: false,
                relay_says: format!("content 超过 {MAX_PAYLOAD_BYTES} 字节上限"),
                messages: 0,
            }),
        );
    }

    let now = now_secs();
    let mut devices = state.prp_devices.lock().await;

    // Take the record out instead of borrowing it in place: an expired lease has
    // to be dropped, and removing from the map while holding a `&mut` to its
    // value is a double mutable borrow. Take-and-reinsert under the same lock is
    // equivalent and conflict-free.
    let Some(mut device) = devices.remove(&device_id) else {
        return (
            StatusCode::NOT_FOUND,
            Json(MessageResponse {
                ok: false,
                relay_says: "device_id 未注册".to_string(),
                messages: 0,
            }),
        );
    };

    if !lease_live(device.last_seen, now) {
        // The `remove` above already dropped the expired record.
        return (
            StatusCode::NOT_FOUND,
            Json(MessageResponse {
                ok: false,
                relay_says: "租约已过期，请重新注册".to_string(),
                messages: 0,
            }),
        );
    }

    device.self_check = payload.content;
    device.last_seen = now;
    device.messages += 1;

    let alias = device.alias.clone();
    let messages = device.messages;
    let age = now.saturating_sub(device.registered_at);
    let lease_left = LEASE_SECS.saturating_sub(age.min(LEASE_SECS));
    devices.insert(device_id, device);
    drop(devices);

    tracing::info!("PRP relay: message #{messages} from {device_id} ({alias:?})");

    (
        StatusCode::OK,
        Json(MessageResponse {
            ok: true,
            relay_says: format!("echo: {alias} 第 {messages} 条自检已入库，租约剩余 {lease_left} 秒"),
            messages,
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(value: &str) -> serde_json::Value {
        serde_json::json!({ "probe": value })
    }

    #[test]
    fn alias_falls_back_to_default_when_blank() {
        assert_eq!(sanitize_alias(""), "LocalSend");
        assert_eq!(sanitize_alias("   "), "LocalSend");
        assert_eq!(sanitize_alias("  phone-a  "), "phone-a");
    }

    #[test]
    fn alias_is_truncated_to_the_limit() {
        let long = "x".repeat(MAX_ALIAS_CHARS + 40);
        assert_eq!(sanitize_alias(&long).chars().count(), MAX_ALIAS_CHARS);
    }

    #[test]
    fn lease_expires_exactly_at_the_limit() {
        assert!(lease_live(100, 100 + LEASE_SECS - 1));
        assert!(!lease_live(100, 100 + LEASE_SECS));
        // A clock that jumps backwards must not extend the lease forever.
        assert!(lease_live(200, 100));
    }

    #[tokio::test]
    async fn register_then_message_completes_the_handshake() {
        let state = AppState::new();

        let (status, Json(reg)) = register(
            State(state.clone()),
            Json(RegisterRequest {
                alias: " phone-a ".to_string(),
                self_check: payload("first"),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert!(reg.ok);
        assert!(!reg.device_id.is_empty());
        assert_eq!(reg.lease_secs, LEASE_SECS);
        assert!(reg.instruction.contains("phone-a"));

        {
            let devices = state.prp_devices.lock().await;
            assert_eq!(devices.len(), 1);
            let stored = devices.values().next().unwrap();
            assert_eq!(stored.alias, "phone-a");
            assert_eq!(stored.messages, 0);
        }

        let (status, Json(msg)) = message(
            State(state.clone()),
            Json(MessageRequest {
                device_id: reg.device_id.clone(),
                content: payload("second"),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert!(msg.ok);
        assert_eq!(msg.messages, 1);
        assert!(msg.relay_says.starts_with("echo: phone-a"));

        let devices = state.prp_devices.lock().await;
        let stored = devices.values().next().unwrap();
        // The latest self-check replaces the one sent at registration.
        assert_eq!(stored.self_check["probe"], "second");
        assert_eq!(stored.messages, 1);
    }

    #[tokio::test]
    async fn message_rejects_unknown_and_malformed_ids() {
        let state = AppState::new();

        let (status, Json(msg)) = message(
            State(state.clone()),
            Json(MessageRequest {
                device_id: Uuid::new_v4().to_string(),
                content: payload("x"),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert!(!msg.ok);

        let (status, Json(msg)) = message(
            State(state.clone()),
            Json(MessageRequest {
                device_id: "not-a-uuid".to_string(),
                content: payload("x"),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert!(!msg.ok);
    }

    #[tokio::test]
    async fn oversized_self_check_is_refused() {
        let state = AppState::new();
        let huge = "a".repeat(MAX_PAYLOAD_BYTES + 1);

        let (status, Json(reg)) = register(
            State(state.clone()),
            Json(RegisterRequest {
                alias: "phone-a".to_string(),
                self_check: payload(&huge),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
        assert!(!reg.ok);
        assert!(state.prp_devices.lock().await.is_empty());
    }
}
