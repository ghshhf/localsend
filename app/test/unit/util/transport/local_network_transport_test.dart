import 'dart:async';

import 'package:localsend_app/util/transport/local_network_transport.dart';
import 'package:localsend_app/util/transport/transport_interface.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:test/test.dart';

/// Stands in for the app-wide discovery. Records what the transport asks of it
/// and lets the test push device sets.
class _FakeLanDiscovery implements LanDiscovery {
  final Map<String, Device> store = {};
  final StreamController<Map<String, Device>> controller = StreamController<Map<String, Device>>.broadcast();

  int announceCount = 0;
  int probeCount = 0;

  /// When set, [probe] waits for it, so a test can hold a probe in flight.
  Completer<void>? probeGate;

  @override
  Map<String, Device> get snapshot => Map<String, Device>.unmodifiable(store);

  @override
  Stream<Map<String, Device>> get changes => controller.stream;

  @override
  void announce() => announceCount++;

  @override
  Future<void> probe() {
    probeCount++;
    final gate = probeGate;
    return gate == null ? Future<void>.value() : gate.future;
  }

  /// Pushes the current store as a new device set, the way the Rust discovery
  /// does on every confirmation.
  void emit() => controller.add(Map<String, Device>.of(store));
}

Device _device(
  String fingerprint, {
  String? ip = '192.168.0.42',
  String alias = 'phone',
  int port = 53317,
}) {
  return Device(
    signalingId: null,
    ip: ip,
    version: '2.1',
    port: port,
    https: false,
    fingerprint: fingerprint,
    alias: alias,
    deviceModel: 'Pixel',
    deviceType: DeviceType.mobile,
    download: true,
    channels: [if (ip != null) HttpChannel(host: ip, port: port, https: false)],
  );
}

void main() {
  group('LocalNetworkTransport', () {
    late _FakeLanDiscovery discovery;
    late LocalNetworkTransport transport;

    setUp(() {
      discovery = _FakeLanDiscovery();
      transport = LocalNetworkTransport(discovery: discovery);
    });

    tearDown(() async {
      await transport.dispose();
      await discovery.controller.close();
    });

    test('isAvailable is false without a discovery source', () {
      final orphan = LocalNetworkTransport();
      expect(orphan.isAvailable, isFalse);
      expect(orphan.type, TransportType.localNetwork);
    });

    test('start fails with a readable error when no discovery is attached', () async {
      final orphan = LocalNetworkTransport();

      final started = await orphan.start(config: const HostConfig(alias: 'LocalSend'));

      expect(started, isFalse);
      expect(orphan.state, TransportState.error);
      expect(orphan.errorMessage, contains('No LAN discovery'));
    });

    test('start announces and replays devices confirmed before it started', () async {
      discovery.store['fp1'] = _device('fp1', alias: 'already-here');

      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      final started = await transport.start(config: const HostConfig(alias: 'LocalSend'));
      await Future<void>.delayed(Duration.zero);

      expect(started, isTrue);
      expect(transport.state, TransportState.connected);
      // The shared discovery has been running for a while; the caller needs the
      // devices it already knows, not only future confirmations.
      expect(peers.map((p) => p.id), ['fp1']);
      expect(discovery.announceCount, 1);
    });

    test('devices confirmed later arrive as peers', () async {
      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      discovery.store['fp2'] = _device('fp2', ip: '192.168.0.77', alias: 'tablet', port: 53318);
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      expect(peers, hasLength(1));
      expect(peers.single.id, 'fp2');
      expect(peers.single.alias, 'tablet');
      expect(peers.single.ipAddress, '192.168.0.77');
      expect(peers.single.port, 53318);
      expect(peers.single.transportType, TransportType.localNetwork);
    });

    test('an unchanged device is not re-emitted when another one is confirmed', () async {
      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      discovery.store['fp1'] = _device('fp1');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      // The discovery sends the whole set on every confirmation, so a new
      // device carries the old one along.
      discovery.store['fp2'] = _device('fp2');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      expect(peers.map((p) => p.id), ['fp1', 'fp2']);
    });

    test('a re-confirmed device with new data is emitted again', () async {
      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      discovery.store['fp1'] = _device('fp1', alias: 'old-name');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      discovery.store['fp1'] = _device('fp1', alias: 'new-name');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      expect(peers.map((p) => p.alias), ['old-name', 'new-name']);
    });

    test('a device without a LAN address is skipped', () async {
      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      // Devices reached only through a signaling server have no IP.
      discovery.store['signaling'] = _device('signaling', ip: null);
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      expect(peers, isEmpty);
    });

    test('stop drops the subscription but leaves the shared discovery running', () async {
      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      await transport.stop();

      expect(transport.state, TransportState.disconnected);
      expect(transport.transportInfo, isNull);
      // The app-wide discovery must survive a PRP disconnect: stopping it here
      // would blank the device list as a side effect.
      expect(discovery.controller.hasListener, isFalse);
      expect(discovery.controller.isClosed, isFalse);
    });

    test('a second start is idempotent and does not double-subscribe', () async {
      await transport.start(config: const HostConfig(alias: 'LocalSend'));
      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      discovery.store['fp1'] = _device('fp1');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      // A double subscription would deliver the same peer twice.
      expect(peers.map((p) => p.id), ['fp1']);
      // Both starts still announce: each is a request to be findable.
      expect(discovery.announceCount, 2);
    });

    test('restarting after stop replays the devices again', () async {
      await transport.start(config: const HostConfig(alias: 'LocalSend'));
      discovery.store['fp1'] = _device('fp1');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      await transport.stop();

      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);
      await transport.start(config: const HostConfig(alias: 'LocalSend'));
      await Future<void>.delayed(Duration.zero);

      expect(peers.map((p) => p.id), ['fp1']);
    });

    test('connect starts the transport when needed and probes the network', () async {
      final started = await transport.connect(
        config: const ConnectConfig(ssid: '', password: ''),
      );

      expect(started, isTrue);
      expect(transport.state, TransportState.connected);
      expect(discovery.probeCount, 1);
      expect(discovery.announceCount, 1);
    });

    test('connect reports a probe failure', () async {
      final failing = _FailingProbeDiscovery();
      final failingTransport = LocalNetworkTransport(discovery: failing);
      addTearDown(failingTransport.dispose);

      final connected = await failingTransport.connect(
        config: const ConnectConfig(ssid: '', password: ''),
      );

      expect(connected, isFalse);
      expect(failingTransport.state, TransportState.error);
      expect(failingTransport.errorMessage, contains('probe failed'));
    });

    test('transportInfo reports the peer count instead of an SSID', () async {
      await transport.start(config: const HostConfig(alias: 'LocalSend'));
      discovery.store['fp1'] = _device('fp1');
      discovery.store['fp2'] = _device('fp2');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      final info = transport.transportInfo;
      expect(info, isNotNull);
      expect(info!.type, TransportType.localNetwork);
      expect(info.networkName, isNull);
      expect(info.password, isNull);
      expect(info.metadata['peers'], 2);
    });

    test('devices found while the probe runs are not dropped', () async {
      final gate = Completer<void>();
      discovery.probeGate = gate;

      final peers = <PeerInfo>[];
      transport.onPeerDiscovered.listen(peers.add);

      final connecting = transport.connect(
        config: const ConnectConfig(ssid: '', password: ''),
      );
      await Future<void>.delayed(Duration.zero);

      // Discovery results arrive while the transport is still in "connecting".
      discovery.store['fp1'] = _device('fp1');
      discovery.emit();
      await Future<void>.delayed(Duration.zero);

      gate.complete();
      await connecting;

      expect(peers.map((p) => p.id), ['fp1']);
      expect(transport.transportInfo!.metadata['peers'], 1);
    });

    test('a stop during the probe is not undone when the probe finishes', () async {
      final gate = Completer<void>();
      discovery.probeGate = gate;

      final connecting = transport.connect(
        config: const ConnectConfig(ssid: '', password: ''),
      );
      await Future<void>.delayed(Duration.zero);

      await transport.stop();
      gate.complete();
      final connected = await connecting;

      // The probe completing late must not put the transport back into a live
      // state after the user disconnected.
      expect(connected, isFalse);
      expect(transport.state, TransportState.disconnected);
    });

    test('dispose is idempotent and closes the streams', () async {
      await transport.start(config: const HostConfig(alias: 'LocalSend'));

      await transport.dispose();
      await transport.dispose();

      expect(transport.isAvailable, isFalse);
    });
  });
}

class _FailingProbeDiscovery extends _FakeLanDiscovery {
  @override
  Future<void> probe() async => throw StateError('probe failed');
}
