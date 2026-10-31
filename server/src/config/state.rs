use localsend::webrtc::signaling::{ClientInfoWithoutId, WsServerMessage};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use uuid::Uuid;

/// IP -> Peer ID -> PeerInfo + WebSocket message sender.
pub type TxMap = Arc<Mutex<HashMap<String, HashMap<Uuid, ClientState>>>>;

pub struct ClientState {
    pub client: ClientInfoWithoutId,
    pub tx: mpsc::Sender<WsServerMessage>,
}

pub type IpRequestCountMap = Arc<Mutex<HashMap<String, u32>>>;

/// A device registered against the PRP relay bridge.
///
/// The relay is a rendezvous point, not a message broker: it keeps the latest
/// self-check a device reported so a future peer can read it, and nothing else.
pub struct PrpDevice {
    pub alias: String,
    pub self_check: serde_json::Value,
    /// Unix seconds when the device registered.
    pub registered_at: u64,
    /// Unix seconds of the last `/api/prp/message` call.
    pub last_seen: u64,
    /// How many messages this device has sent since registering.
    pub messages: u32,
}

/// Device ID -> `PrpDevice`.
pub type PrpDeviceMap = Arc<Mutex<HashMap<Uuid, PrpDevice>>>;

#[derive(Clone)]
pub struct AppState {
    /// Map of peer IDs to WebSocket message senders.
    pub tx_map: TxMap,

    /// Map of IP addresses to the number of requests.
    pub request_count_map: IpRequestCountMap,

    /// Map of PRP relay device IDs to their registration state.
    pub prp_devices: PrpDeviceMap,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            tx_map: Arc::new(Mutex::new(HashMap::new())),
            request_count_map: Arc::new(Mutex::new(HashMap::new())),
            prp_devices: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}
