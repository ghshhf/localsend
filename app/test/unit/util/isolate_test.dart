import 'package:common/model/device.dart';
import 'package:common/src/isolate/parent/actions.dart';
import 'package:test/test.dart';

void main() {
  group('IsolateInterfaceHttpDiscoveryAction', () {
    test('should accept required parameters', () {
      final action = IsolateInterfaceHttpDiscoveryAction(
        networkInterface: '192.168.1.1',
        port: 8080,
        https: false,
      );

      expect(action.networkInterface, '192.168.1.1');
      expect(action.port, 8080);
      expect(action.https, false);
    });

    test('https parameter should affect protocol', () {
      final httpAction = IsolateInterfaceHttpDiscoveryAction(
        networkInterface: '192.168.1.1',
        port: 8080,
        https: false,
      );

      final httpsAction = IsolateInterfaceHttpDiscoveryAction(
        networkInterface: '192.168.1.1',
        port: 443,
        https: true,
      );

      expect(httpAction.https, false);
      expect(httpsAction.https, true);
    });
  });

  group('IsolateFavoriteHttpDiscoveryAction', () {
    test('should accept favorites list', () {
      final action = IsolateFavoriteHttpDiscoveryAction(
        favorites: [
          ('192.168.1.2', 8080),
          ('192.168.1.3', 8080),
        ],
        https: false,
      );

      expect(action.favorites, hasLength(2));
      expect(action.favorites.first.$1, '192.168.1.2');
      expect(action.favorites.first.$2, 8080);
    });

    test('should handle empty favorites', () {
      final action = IsolateFavoriteHttpDiscoveryAction(
        favorites: [],
        https: false,
      );

      expect(action.favorites, isEmpty);
    });
  });

  group('IsolateSendMulticastAnnouncementAction', () {
    test('can be instantiated', () {
      final action = IsolateSendMulticastAnnouncementAction();
      expect(action, isNotNull);
    });
  });

  group('IsolateSendMulticastRestartListenerAction', () {
    test('can be instantiated', () {
      final action = IsolateSendMulticastRestartListenerAction();
      expect(action, isNotNull);
    });
  });

  group('IsolateHttpUploadAction', () {
    test('should accept required parameters', () {
      final device = _mockDevice();
      final action = IsolateHttpUploadAction(
        isolateIndex: 0,
        remoteSessionId: 'remote-session-1',
        remoteFileToken: 'token-1',
        fileId: 'file-1',
        filePath: '/path/to/file.txt',
        fileBytes: null,
        mime: 'text/plain',
        fileSize: 100,
        device: device,
      );

      expect(action.isolateIndex, 0);
      expect(action.remoteSessionId, 'remote-session-1');
      expect(action.remoteFileToken, 'token-1');
      expect(action.fileId, 'file-1');
      expect(action.filePath, '/path/to/file.txt');
      expect(action.mime, 'text/plain');
      expect(action.fileSize, 100);
    });

    test('should handle null filePath with fileBytes', () {
      final device = _mockDevice();
      final action = IsolateHttpUploadAction(
        isolateIndex: 0,
        remoteSessionId: null,
        remoteFileToken: 'token-1',
        fileId: 'file-1',
        filePath: null,
        fileBytes: [1, 2, 3],
        mime: 'application/octet-stream',
        fileSize: 3,
        device: device,
      );

      expect(action.filePath, isNull);
      expect(action.fileBytes, isNotNull);
      expect(action.fileBytes, hasLength(3));
    });
  });

  group('IsolateHttpUploadCancelAction', () {
    test('should accept isolateIndex and taskId', () {
      final action = IsolateHttpUploadCancelAction(
        isolateIndex: 0,
        taskId: 42,
      );

      expect(action.isolateIndex, 0);
      expect(action.taskId, 42);
    });
  });

  group('IsolateHttpUploadActionResult', () {
    test('should hold taskId and progress stream', () {
      final result = IsolateHttpUploadActionResult(
        taskId: 1,
        progress: Stream.value(0.5),
      );

      expect(result.taskId, 1);
      expect(result.progress, isA<Stream<double>>());
    });
  });
}

Device _mockDevice() {
  return Device(
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
}
