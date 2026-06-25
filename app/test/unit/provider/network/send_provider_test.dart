import 'package:common/model/device.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/session_status.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:test/test.dart';

void main() {
  group('SendingFile', () {
    test('initial status should be queue', () {
      final file = SendingFile(
        file: FileDto(
          id: 'test-id',
          fileName: 'test.txt',
          size: 100,
          fileType: FileType.other,
          hash: null,
          preview: null,
          metadata: null,
        ),
        status: FileStatus.queue,
        token: null,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: null,
        errorMessage: null,
      );

      expect(file.status, FileStatus.queue);
      expect(file.file.fileName, 'test.txt');
      expect(file.file.size, 100);
    });

    test('copyWith should update status', () {
      final file = SendingFile(
        file: FileDto(
          id: 'test-id',
          fileName: 'test.txt',
          size: 100,
          fileType: FileType.other,
          hash: null,
          preview: null,
          metadata: null,
        ),
        status: FileStatus.queue,
        token: null,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: null,
        errorMessage: null,
      );

      final updated = file.copyWith(status: FileStatus.sending);
      expect(updated.status, FileStatus.sending);
      expect(updated.file.fileName, 'test.txt'); // Unchanged
    });
  });

  group('SendSessionState', () {
    test('initial state should have correct defaults', () {
      final state = SendSessionState(
        sessionId: 'session-1',
        remoteSessionId: null,
        background: false,
        status: SessionStatus.waiting,
        target: _mockDevice(),
        files: {},
        startTime: null,
        endTime: null,
        sendingTasks: [],
        errorMessage: null,
      );

      expect(state.sessionId, 'session-1');
      expect(state.status, SessionStatus.waiting);
      expect(state.background, false);
      expect(state.files, isEmpty);
    });

    test('copyWith should update status', () {
      final state = SendSessionState(
        sessionId: 'session-1',
        remoteSessionId: null,
        background: false,
        status: SessionStatus.waiting,
        target: _mockDevice(),
        files: {},
        startTime: null,
        endTime: null,
        sendingTasks: [],
        errorMessage: null,
      );

      final updated = state.copyWith(status: SessionStatus.sending);
      expect(updated.status, SessionStatus.sending);
      expect(updated.sessionId, 'session-1'); // Unchanged
    });

    test('status transition: waiting -> sending -> finished', () {
      final state = SendSessionState(
        sessionId: 's1',
        remoteSessionId: null,
        background: false,
        status: SessionStatus.waiting,
        target: _mockDevice(),
        files: {},
        startTime: null,
        endTime: null,
        sendingTasks: [],
        errorMessage: null,
      );

      expect(state.status, SessionStatus.waiting);

      final sending = state.copyWith(status: SessionStatus.sending);
      expect(sending.status, SessionStatus.sending);

      final finished = sending.copyWith(status: SessionStatus.finished);
      expect(finished.status, SessionStatus.finished);
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
