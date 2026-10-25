import 'dart:async';

import 'package:localsend_app/util/transport/transport_interface.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';

final _logger = Logger('LocalNetworkTransport');

/// The LAN discovery that [LocalNetworkTransport] observes.
///
/// The app already runs discovery for its device list (Rust multicast with an
/// HTTP subnet fallback). That discovery binds a fixed UDP port, so a transport
/// must not start a second one: the second bind loses multicast ("port is
/// taken") and splits the confirmed devices into two stores. This interface is
/// the narrow view the transport needs, which keeps it testable without Rust or
/// a network.
abstract class LanDiscovery {
  /// The devices confirmed so far, keyed by fingerprint.
  Map<String, Device> get snapshot;

  /// Every change of the confirmed device set, carrying the whole set.
  ///
  /// Broadcast: the transport may subscribe, unsubscribe and resubscribe
  /// without disturbing the discovery itself.
  Stream<Map<String, Device>> get changes;

  /// Tells the network that this device is online, which makes every other
  /// LocalSend device on it register with this one.
  void announce();

  /// Discovers in stages, cheapest first: announces this device and probes the
  /// known favorites, then scans the local subnets for networks that do not
  /// carry multicast. Completes once every stage has finished.
  Future<void> probe();
}

/// LAN transport: the device stays on its current network and finds peers
/// there, instead of building a network (WiFi hotspot) or using a cable (USB
/// tethering).
///
/// This is the fallback the PRP roadmap asks for: when a hotspot cannot be
/// started, the peers are usually still reachable over the shared network, and
/// LocalSend's normal discovery already knows how to find them.
///
/// The transport is a **peer**, not a host: [start] means "join the network and
/// be findable", [connect] means "join and look for peers". There is no SSID and
/// no password to manage, so the corresponding [HostConfig] and [ConnectConfig]
/// fields are ignored.
class LocalNetworkTransport implements TransportInterface {
  LocalNetworkTransport({LanDiscovery? discovery}) : _discovery = discovery;

  static const _noDiscovery = 'No LAN discovery source is attached';

  /// A probe over a large subnet can take a while. The probe is not cancelled
  /// on timeout — peers keep arriving on the stream — but the caller gets
  /// control back instead of waiting for a silent network to finish scanning.
  static const _probeTimeout = Duration(seconds: 20);

  final LanDiscovery? _discovery;

  TransportState _state = TransportState.idle;
  TransportInfo? _transportInfo;
  String? _error;
  StreamSubscription<Map<String, Device>>? _subscription;
  bool _disposed = false;

  /// Devices already pushed to listeners. Discovery emits the whole set on
  /// every confirmation, so without this an unchanged device would be re-emitted
  /// on every unrelated confirmation.
  final Map<String, Device> _emitted = {};

  final StreamController<PeerInfo> _peerController = StreamController<PeerInfo>.broadcast();
  final StreamController<TransportState> _stateController = StreamController<TransportState>.broadcast();

  @override
  TransportType get type => TransportType.localNetwork;

  @override
  TransportState get state => _state;

  @override
  TransportInfo? get transportInfo => _transportInfo;

  @override
  String? get errorMessage => _state == TransportState.error ? _error : null;

  /// The LAN transport is usable when LAN discovery exists — every platform
  /// LocalSend runs on has one, so this is in practice a "did the app hand us
  /// the discovery" check.
  @override
  bool get isAvailable => !_disposed && _discovery != null;

  @override
  Stream<PeerInfo> get onPeerDiscovered => _peerController.stream;

  @override
  Stream<TransportState> get onStateChanged => _stateController.stream;

  /// Joins the network: announces this device and watches the shared discovery.
  ///
  /// [config]'s alias is ignored — the alias of an announced device comes from
  /// the app-wide settings, not from the PRP host form.
  @override
  Future<bool> start({required HostConfig config}) async {
    if (_disposed) return false;

    final discovery = _discovery;
    if (discovery == null) {
      _setError(_noDiscovery);
      return false;
    }

    if (_subscription != null) {
      // Already attached: a new start is a new request to be findable, but it
      // must never subscribe a second time (that would emit every peer twice).
      discovery.announce();
      if (_state != TransportState.connected && _state != TransportState.connecting) {
        _transportInfo = _buildInfo(discovery.snapshot.length);
        _setState(TransportState.connected);
      }
      return true;
    }

    _setState(TransportState.connecting);

    try {
      _subscription = discovery.changes.listen(
        _onDevicesChanged,
        onError: (Object e, StackTrace st) {
          _logger.warning('LAN discovery stream failed: $e', e, st);
        },
      );
    } catch (e, st) {
      _logger.warning('Cannot listen to LAN discovery: $e', e, st);
      _setError('Cannot listen to LAN discovery: $e');
      return false;
    }

    // Replay what is already known: the shared discovery has likely confirmed
    // devices long before this transport started, and the caller needs the
    // current picture rather than only future confirmations.
    _emit(discovery.snapshot);

    discovery.announce();

    _transportInfo = _buildInfo(discovery.snapshot.length);
    _setState(TransportState.connected);
    return true;
  }

  /// Leaves the transport.
  ///
  /// Deliberately does not stop the discovery: it is shared with the device
  /// list, and stopping it here would blank the send tab as a side effect of
  /// closing a PRP connection.
  @override
  Future<void> stop() async {
    await _detach();
    _transportInfo = null;
    if (_disposed) return;
    _setState(TransportState.disconnected);
  }

  /// Joins the network and actively looks for peers.
  ///
  /// [config]'s SSID and password are ignored: the device is already on a
  /// network, so there is nothing to authenticate against. The fields stay
  /// required by [TransportInterface] because the hotspot transport needs them.
  @override
  Future<bool> connect({required ConnectConfig config}) async {
    if (_disposed) return false;

    final discovery = _discovery;
    if (discovery == null) {
      _setError(_noDiscovery);
      return false;
    }

    if (_state != TransportState.connected) {
      final started = await start(config: HostConfig(alias: config.ssid));
      if (!started) return false;
    }

    _setState(TransportState.connecting);

    try {
      await discovery.probe().timeout(_probeTimeout);
    } on TimeoutException {
      // Not a failure: the probe is still running and peers will keep arriving
      // on the device stream. Reporting an error here would flash a red state
      // on a large subnet that simply has not answered yet.
      _logger.warning('LAN probe still running after ${_probeTimeout.inSeconds}s; peers keep arriving on the stream');
    } catch (e, st) {
      _logger.warning('LAN probe failed: $e', e, st);
      _setError('LAN probe failed: $e');
      return false;
    }

    if (_disposed) return false;

    // A stop during the probe must win: setting "connected" here would put the
    // UI back into a live state after the user disconnected.
    if (_state != TransportState.connecting) {
      return _state == TransportState.connected;
    }

    _transportInfo = _buildInfo(_emitted.length);
    _setState(TransportState.connected);
    return true;
  }

  @override
  Future<void> disconnect() => stop();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _detach();
    _transportInfo = null;
    await _peerController.close();
    await _stateController.close();
  }

  Future<void> _detach() async {
    final subscription = _subscription;
    _subscription = null;
    // Clear the emitted set so a later start replays the current devices
    // instead of treating them as already pushed.
    _emitted.clear();
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } catch (e, st) {
      _logger.warning('Error cancelling LAN discovery subscription', e, st);
    }
  }

  void _onDevicesChanged(Map<String, Device> devices) {
    // Devices are accepted while connecting too: [connect] probes in that
    // state, and the devices the probe finds are the whole point of it.
    if (_disposed || _subscription == null) return;
    _emit(devices);
    // Keep the peer count current: the UI shows it instead of an SSID.
    _transportInfo = _buildInfo(devices.length);
  }

  void _emit(Map<String, Device> devices) {
    if (_peerController.isClosed) return;

    devices.forEach((fingerprint, device) {
      // Discovery re-emits the whole set; only forward what actually changed.
      if (_emitted[fingerprint] == device) return;

      final peer = _toPeer(device);
      if (peer == null) return;

      _emitted[fingerprint] = device;
      _peerController.add(peer);
    });

    // Forget devices the discovery dropped (favorites removed, store cleared),
    // so they are emitted again if they come back.
    _emitted.removeWhere((fingerprint, _) => !devices.containsKey(fingerprint));
  }

  /// Maps a discovered device to a peer, or null when it is not reachable over
  /// this transport.
  PeerInfo? _toPeer(Device device) {
    final ip = device.ip;
    if (ip == null || ip.isEmpty) {
      // Devices found only through a signaling server have no LAN address.
      return null;
    }

    return PeerInfo(
      id: device.fingerprint,
      alias: device.alias,
      ipAddress: ip,
      port: device.port,
      transportType: TransportType.localNetwork,
      metadata: {
        'https': device.https,
        'version': device.version,
        'deviceModel': device.deviceModel,
        'deviceType': device.deviceType.name,
        'download': device.download,
      },
    );
  }

  TransportInfo _buildInfo(int peerCount) {
    return TransportInfo(
      type: TransportType.localNetwork,
      isRunning: true,
      metadata: {
        // The hotspot transport reports an SSID; a LAN transport joins an
        // existing network instead, so the peer count is what the UI can show.
        'mode': 'peer',
        'peers': peerCount,
      },
    );
  }

  void _setState(TransportState next) {
    if (_disposed) return;
    _state = next;
    if (next != TransportState.error) _error = null;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _setError(String message) {
    if (_disposed) return;
    _error = message;
    _transportInfo = null;
    _logger.warning(message);
    _state = TransportState.error;
    if (!_stateController.isClosed) _stateController.add(TransportState.error);
  }
}
