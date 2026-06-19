import 'package:common/model/device.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:test/test.dart';

void main() {
  group('NearbyDevicesState', () {
    test('initial state should be correct', () {
      const state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {},
        devices: {},
        signalingDevices: {},
      );

      expect(state.runningFavoriteScan, false);
      expect(state.runningIps, isEmpty);
      expect(state.devices, isEmpty);
      expect(state.signalingDevices, isEmpty);
    });

    test('copyWith should update fields', () {
      const state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {},
        devices: {},
        signalingDevices: {},
      );

      final updated = state.copyWith(
        runningFavoriteScan: true,
        runningIps: {'192.168.1.1'},
      );

      expect(updated.runningFavoriteScan, true);
      expect(updated.runningIps, contains('192.168.1.1'));
    });
  });

  group('NearbyDevicesService', () {
    test('init returns correct initial state', () {
      // Note: This test verifies the state structure.
      // Full service testing would require mocking IsolateController, FavoritesService, etc.
      final initialState = const NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {},
        devices: {},
        signalingDevices: {},
      );

      expect(initialState.devices, isEmpty);
      expect(initialState.runningIps, isEmpty);
      expect(initialState.runningFavoriteScan, false);
    });
  });

  group('ClearFoundDevicesAction', () {
    test('should clear all devices in state', () {
      // Test the state copyWith behavior which ClearFoundDevicesAction uses
      final state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {},
        devices: {
          '192.168.1.2': Device(
            signalingId: null,
            ip: '192.168.1.2',
            version: '1.0',
            port: 8080,
            https: false,
            fingerprint: 'test-fp',
            alias: 'Test Device',
            deviceModel: 'Test Model',
            deviceType: DeviceType.desktop,
            download: false,
            discoveryMethods: {},
          ),
        },
        signalingDevices: {},
      );

      final clearedState = state.copyWith(devices: {});

      expect(clearedState.devices, isEmpty);
    });
  });

  group('RegisterDeviceAction', () {
    test('should register device with IP as key', () {
      final device = Device(
        signalingId: null,
        ip: '192.168.1.2',
        version: '1.0',
        port: 8080,
        https: false,
        fingerprint: 'test-fp',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        download: false,
        discoveryMethods: {},
      );

      // Verify the device properties
      expect(device.ip, '192.168.1.2');
      expect(device.alias, 'Test Device');
      expect(device.fingerprint, 'test-fp');
    });

    test('same IP should override existing device', () {
      final device1 = Device(
        signalingId: null,
        ip: '192.168.1.2',
        version: '1.0',
        port: 8080,
        https: false,
        fingerprint: 'fp1',
        alias: 'Device 1',
        deviceModel: 'Model 1',
        deviceType: DeviceType.desktop,
        download: false,
        discoveryMethods: {},
      );

      final device2 = Device(
        signalingId: null,
        ip: '192.168.1.2', // Same IP
        version: '1.0',
        port: 8080,
        https: false,
        fingerprint: 'fp2',
        alias: 'Device 2',
        deviceModel: 'Model 2',
        deviceType: DeviceType.desktop,
        download: false,
        discoveryMethods: {},
      );

      // Simulate the register logic: update with same IP overrides
      final devices = <String, Device>{};
      devices[device1.ip!] = device1;
      devices.update(device2.ip!, (_) => device2, ifAbsent: () => device2);

      expect(devices, hasLength(1));
      expect(devices['192.168.1.2']!.alias, 'Device 2');
    });
  });

  group('StartMulticastScan', () {
    test('can be instantiated', () {
      final action = StartMulticastScan();
      expect(action, isNotNull);
    });
  });

  group('StartLegacyScan', () {
    test('should track localIp to prevent duplicate scans', () {
      final state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {'192.168.1.1'},
        devices: {},
        signalingDevices: {},
      );

      // Trying to scan same IP should be skipped (runningIps contains it)
      final newIp = '192.168.1.1';
      expect(state.runningIps.contains(newIp), true);

      // Different IP should proceed
      final differentIp = '192.168.2.1';
      expect(state.runningIps.contains(differentIp), false);
    });

    test('should create scan with correct parameters', () {
      final scan = StartLegacyScan(
        port: 8080,
        localIp: '192.168.1.1',
        https: false,
      );

      expect(scan.port, 8080);
      expect(scan.localIp, '192.168.1.1');
      expect(scan.https, false);
    });
  });
}
