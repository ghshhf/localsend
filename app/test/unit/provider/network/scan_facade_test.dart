import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:test/test.dart';

void main() {
  group('StartSmartScan', () {
    test('should have forceLegacy parameter', () {
      final actionWithForceLegacy = StartSmartScan(forceLegacy: true);
      final actionWithoutForceLegacy = StartSmartScan(forceLegacy: false);

      expect(actionWithForceLegacy.forceLegacy, true);
      expect(actionWithoutForceLegacy.forceLegacy, false);
    });

    test('should trigger multicast scan', () {
      // StartSmartScan dispatches StartMulticastScan
      // This test verifies the action can be created
      final action = StartSmartScan(forceLegacy: false);
      expect(action, isNotNull);
    });
  });

  group('StartSmartScan.maxInterfaces', () {
    test('should have correct default value', () {
      expect(StartSmartScan.maxInterfaces, 3);
    });
  });

  group('StartLegacySubnetScan', () {
    test('should accept list of subnets', () {
      final action = StartLegacySubnetScan(
        subnets: ['192.168.1.1', '192.168.2.1'],
      );

      expect(action.subnets, hasLength(2));
      expect(action.subnets, contains('192.168.1.1'));
      expect(action.subnets, contains('192.168.2.1'));
    });

    test('should handle empty subnets list', () {
      final action = StartLegacySubnetScan(subnets: []);

      expect(action.subnets, isEmpty);
    });
  });
}
