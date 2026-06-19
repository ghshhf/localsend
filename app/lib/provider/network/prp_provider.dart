import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/hotspot_relay.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PrpProvider');

/// PRP (Peer Relay Protocol) modes
enum PrpMode {
  /// Device creates a hotspot and waits for peers
  host,

  /// Device scans/connects to a peer's hotspot
  client,

  /// No PRP activity
  idle,
}

/// PRP connection state
enum PrpConnectionState {
  /// Initial state
  idle,

  /// Starting hotspot / connecting to hotspot
  connecting,

  /// Hotspot is running / connected to peer hotspot
  connected,

  /// Transfer in progress
  transferring,

  /// Error occurred
  error,

  /// Disconnected
  disconnected,
}

/// PRP (Peer Relay Protocol) provider.
///
/// Manages the lifecycle of hotspot-based peer relay connections.
/// When devices cannot discover each other on the same LAN, PRP
/// creates a temporary local network via WiFi hotspot.
class PrpProvider extends ChangeNotifier {
  PrpMode _mode = PrpMode.idle;
  PrpConnectionState _state = PrpConnectionState.idle;
  HotspotInfo _hotspotInfo = const HotspotInfo(ssid: '', password: '', isRunning: false);
  String? _errorMessage;

  // Getters
  PrpMode get mode => _mode;
  PrpConnectionState get state => _state;
  HotspotInfo get hotspotInfo => _hotspotInfo;
  String? get errorMessage => _errorMessage;
  bool get isActive => _mode != PrpMode.idle;

  // ============================================================
  //  HOST MODE
  // ============================================================

  /// Start PRP in host mode (create hotspot).
  Future<bool> startHostMode() async {
    _logger.info('Starting PRP host mode...');
    _mode = PrpMode.host;
    _state = PrpConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _hotspotInfo = await startHotspot();
      _state = PrpConnectionState.connected;
      notifyListeners();
      _logger.info('PRP host mode active: ${_hotspotInfo.ssid}');
      return true;
    } catch (e) {
      _state = PrpConnectionState.error;
      _errorMessage = 'Failed to start hotspot: $e';
      _logger.severe(_errorMessage);
      notifyListeners();
      return false;
    }
  }

  /// Stop PRP host mode.
  Future<void> stopHostMode() async {
    _logger.info('Stopping PRP host mode...');
    await stopHotspot();
    _mode = PrpMode.idle;
    _state = PrpConnectionState.disconnected;
    _hotspotInfo = const HotspotInfo(ssid: '', password: '', isRunning: false);
    notifyListeners();
  }

  // ============================================================
  //  CLIENT MODE
  // ============================================================

  /// Connect to a peer hotspot in client mode.
  Future<bool> connectToPeer({
    required String ssid,
    required String password,
  }) async {
    _logger.info('Connecting to peer hotspot: $ssid');
    _mode = PrpMode.client;
    _state = PrpConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final connected = await connectToHotspot(
        ssid: ssid,
        password: password,
      );

      if (connected) {
        _state = PrpConnectionState.connected;
        _hotspotInfo = HotspotInfo(
          ssid: ssid,
          password: password,
          isRunning: true,
        );
        notifyListeners();
        _logger.info('Connected to peer hotspot: $ssid');
        return true;
      } else {
        _state = PrpConnectionState.error;
        _errorMessage = 'Failed to connect to hotspot';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _state = PrpConnectionState.error;
      _errorMessage = 'Connection error: $e';
      _logger.severe(_errorMessage);
      notifyListeners();
      return false;
    }
  }

  /// Disconnect client mode.
  Future<void> disconnectFromPeer() async {
    _logger.info('Disconnecting from peer hotspot...');
    await disconnectHotspot();
    _mode = PrpMode.idle;
    _state = PrpConnectionState.disconnected;
    _hotspotInfo = const HotspotInfo(ssid: '', password: '', isRunning: false);
    notifyListeners();
  }

  // ============================================================
  //  HELPERS
  // ============================================================

  /// Refresh hotspot status.
  Future<void> refreshStatus() async {
    if (_mode == PrpMode.host) {
      _hotspotInfo = await getHotspotInfo();
      notifyListeners();
    }
    if (_mode == PrpMode.client) {
      final connected = await isConnectedToHotspot();
      if (!connected && _state == PrpConnectionState.connected) {
        _state = PrpConnectionState.disconnected;
        notifyListeners();
      }
    }
  }

  /// Reset all state.
  void reset() {
    _mode = PrpMode.idle;
    _state = PrpConnectionState.idle;
    _hotspotInfo = const HotspotInfo(ssid: '', password: '', isRunning: false);
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    reset();
    super.dispose();
  }
}
