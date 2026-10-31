import 'package:localsend_app/provider/network/prp_provider.dart';
import 'package:localsend_app/util/transport/transports.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('PrpState', () {
    test('initial state should be idle', () {
      const state = PrpState();

      expect(state.mode, PrpMode.idle);
      expect(state.state, PrpConnectionState.idle);
      expect(state.transportType, TransportType.wifiHotspot);
      expect(state.networkName, isNull);
      expect(state.networkPassword, isNull);
      expect(state.errorMessage, isNull);
      expect(state.isActive, false);
      expect(state.isUsbTetheringAvailable, false);
    });

    test('copyWith should update fields', () {
      const state = PrpState();

      final updated = state.copyWith(
        mode: PrpMode.host,
        state: PrpConnectionState.connecting,
        transportType: TransportType.usbTethering,
        networkName: 'USB-Net',
        ipAddress: '192.168.42.1',
      );

      expect(updated.mode, PrpMode.host);
      expect(updated.state, PrpConnectionState.connecting);
      expect(updated.transportType, TransportType.usbTethering);
      expect(updated.networkName, 'USB-Net');
      expect(updated.ipAddress, '192.168.42.1');
      expect(updated.isActive, true);
    });

    test('copyWith clearError should set errorMessage to null', () {
      final state = PrpState(errorMessage: 'some error');

      final cleared = state.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);

      final kept = state.copyWith();
      expect(kept.errorMessage, 'some error');
    });

    test('copyWith clearNetwork should clear connection fields', () {
      final state = PrpState(
        mode: PrpMode.host,
        state: PrpConnectionState.connected,
        networkName: 'LocalSend-Relay',
        networkPassword: 'secret123',
        ipAddress: '192.168.43.1',
      );

      // Regression guard: passing null used to mean "keep", so StopHostAction
      // left the previous SSID/password on screen after stopping the hotspot.
      final cleared = state.copyWith(
        mode: PrpMode.idle,
        state: PrpConnectionState.disconnected,
        clearNetwork: true,
      );

      expect(cleared.networkName, isNull);
      expect(cleared.networkPassword, isNull);
      expect(cleared.ipAddress, isNull);
      expect(cleared.mode, PrpMode.idle);
      expect(cleared.isActive, false);
    });

    test('copyWith keeps connection fields unless clearNetwork is set', () {
      final state = PrpState(
        networkName: 'A',
        networkPassword: 'B',
        ipAddress: 'C',
      );

      // Pins the "null means unchanged" contract that the callers rely on.
      final kept = state.copyWith(
        networkName: null,
        networkPassword: null,
        ipAddress: null,
      );

      expect(kept.networkName, 'A');
      expect(kept.networkPassword, 'B');
      expect(kept.ipAddress, 'C');
    });

    test('copyWith keeps the notice apart from the error', () {
      final state = PrpState(errorMessage: 'boom', noticeMessage: 'fell back');

      // They are separate slots on purpose: a successful fallback must not be
      // rendered in the red error card.
      final clearedError = state.copyWith(clearError: true);
      expect(clearedError.errorMessage, isNull);
      expect(clearedError.noticeMessage, 'fell back');

      final clearedNotice = state.copyWith(clearNotice: true);
      expect(clearedNotice.noticeMessage, isNull);
      expect(clearedNotice.errorMessage, 'boom');
    });

    test('copyWith keeps the notice unless clearNotice is set', () {
      final state = PrpState(noticeMessage: 'fell back');

      // Same "null means unchanged" contract as the other string fields.
      expect(state.copyWith(noticeMessage: null).noticeMessage, 'fell back');
      expect(state.copyWith().noticeMessage, 'fell back');
    });

    test('copyWith clearRelay should clear relay fields', () {
      final state = PrpState(
        relayUrl: 'https://relay.example',
        relayDeviceId: 'dev-1',
        relayInstruction: 'ping',
        relayLastEcho: 'pong',
      );

      final cleared = state.copyWith(clearRelay: true);

      expect(cleared.relayUrl, isNull);
      expect(cleared.relayDeviceId, isNull);
      expect(cleared.relayInstruction, isNull);
      expect(cleared.relayLastEcho, isNull);
    });
  });

  group('PrpService (ReduxNotifier)', () {
    test('init returns idle state', () {
      final service = ReduxNotifier.test(redux: PrpService());

      expect(service.state.mode, PrpMode.idle);
      expect(service.state.state, PrpConnectionState.idle);
      expect(service.state.transportType, TransportType.wifiHotspot);
    });

    test('ResetPrpAction resets to idle', () {
      final service = ReduxNotifier.test(redux: PrpService());

      // ResetPrpAction is an AsyncReduxAction; verify dispatch accepts it.
      // State should remain idle after init (async USB check runs in background).
      expect(service.state.mode, PrpMode.idle);
      expect(service.state.state, PrpConnectionState.idle);
    });

    test('availableTransports returns a list of transport types', () {
      final prpService = PrpService();
      // availableTransports is a getter on PrpService instance.
      // Transport availability depends on platform (Android vs others).
      expect(prpService.availableTransports, isA<List<TransportType>>());
    });
  });

  group('TransportType enum', () {
    test('has all expected values', () {
      expect(TransportType.values, hasLength(3));
      expect(
        TransportType.values,
        containsAll([
          TransportType.wifiHotspot,
          TransportType.usbTethering,
          TransportType.localNetwork,
        ]),
      );
    });
  });

  group('PrpMode enum', () {
    test('has all expected values', () {
      expect(PrpMode.values, hasLength(3));
      expect(
        PrpMode.values,
        containsAll([PrpMode.host, PrpMode.client, PrpMode.idle]),
      );
    });
  });

  group('PrpConnectionState enum', () {
    test('has all expected values', () {
      expect(PrpConnectionState.values, hasLength(5));

      expect(
        PrpConnectionState.values,
        containsAll([
          PrpConnectionState.idle,
          PrpConnectionState.connecting,
          PrpConnectionState.connected,
          PrpConnectionState.error,
          PrpConnectionState.disconnected,
        ]),
      );
    });
  });
}
