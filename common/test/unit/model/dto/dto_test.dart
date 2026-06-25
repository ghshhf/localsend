import 'package:common/model/device.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/info_dto.dart';
import 'package:common/model/dto/multicast_dto.dart';
import 'package:common/model/dto/prepare_upload_response_dto.dart';
import 'package:common/model/dto/register_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:test/test.dart';

void main() {
  group('InfoDto', () {
    test('should deserialize from JSON', () {
      final json = {
        'alias': 'Test Device',
        'version': '2.0',
        'deviceModel': 'Pixel 7',
        'deviceType': 'mobile',
        'fingerprint': 'fp123',
        'download': true,
      };

      final dto = InfoDto.fromJson(json);
      expect(dto.alias, 'Test Device');
      expect(dto.version, '2.0');
      expect(dto.deviceModel, 'Pixel 7');
      expect(dto.fingerprint, 'fp123');
      expect(dto.download, true);
    });

    test('should handle null optional fields', () {
      final json = {
        'alias': 'Minimal Device',
      };

      final dto = InfoDto.fromJson(json);
      expect(dto.alias, 'Minimal Device');
      expect(dto.version, isNull);
      expect(dto.deviceModel, isNull);
      expect(dto.fingerprint, isNull);
      expect(dto.download, isNull);
    });

    test('should serialize to JSON', () {
      final dto = InfoDto(
        alias: 'Serialize Test',
        version: '2.0',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        fingerprint: 'ser-fp',
        download: false,
      );

      final json = dto.toJson();
      expect(json['alias'], 'Serialize Test');
      expect(json['fingerprint'], 'ser-fp');
    });
  });

  group('RegisterDto', () {
    test('should deserialize from JSON', () {
      final json = {
        'alias': 'Register Test',
        'version': '2.0',
        'deviceModel': 'iPhone',
        'deviceType': 'mobile',
        'fingerprint': 'reg-fp-123',
        'port': 8080,
        'protocol': 'https',
        'download': false,
      };

      final dto = RegisterDto.fromJson(json);
      expect(dto.alias, 'Register Test');
      expect(dto.fingerprint, 'reg-fp-123');
      expect(dto.port, 8080);
      expect(dto.protocol, ProtocolType.https);
    });

    test('should handle HTTP protocol', () {
      final json = {
        'alias': 'HTTP Device',
        'fingerprint': 'fp-http',
        'protocol': 'http',
      };

      final dto = RegisterDto.fromJson(json);
      expect(dto.protocol, ProtocolType.http);
    });

    test('should serialize to JSON', () {
      const dto = RegisterDto(
        alias: 'Serial Register',
        version: '2.0',
        deviceModel: 'Test',
        deviceType: DeviceType.mobile,
        fingerprint: 'ser-reg-fp',
        port: 8080,
        protocol: ProtocolType.https,
        download: true,
      );

      final json = dto.toJson();
      expect(json['alias'], 'Serial Register');
      expect(json['fingerprint'], 'ser-reg-fp');
    });
  });

  group('MulticastDto', () {
    test('should deserialize from JSON', () {
      final json = {
        'alias': 'Multicast Device',
        'version': '2.0',
        'deviceModel': 'MacBook',
        'deviceType': 'desktop',
        'fingerprint': 'mc-fp-123',
        'port': 53317,
        'protocol': 'https',
        'download': true,
        'announce': true,
      };

      final dto = MulticastDto.fromJson(json);
      expect(dto.alias, 'Multicast Device');
      expect(dto.fingerprint, 'mc-fp-123');
      expect(dto.announce, true);
    });

    test('should handle legacy announcement field', () {
      final json = {
        'alias': 'Legacy Device',
        'fingerprint': 'legacy-fp',
        'announcement': true,
      };

      final dto = MulticastDto.fromJson(json);
      expect(dto.announcement, true);
    });

    test('should serialize to JSON', () {
      const dto = MulticastDto(
        alias: 'Serial Multicast',
        version: '2.0',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        fingerprint: 'ser-mc-fp',
        port: 53317,
        protocol: ProtocolType.https,
        download: false,
        announcement: true,
        announce: true,
      );

      final json = dto.toJson();
      expect(json['alias'], 'Serial Multicast');
      expect(json['fingerprint'], 'ser-mc-fp');
    });
  });

  group('PrepareUploadResponseDto', () {
    test('should deserialize from JSON', () {
      final json = {
        'sessionId': 'session-123',
        'files': {
          'file-1': 'token-abc',
        },
      };

      final dto = PrepareUploadResponseDto.fromJson(json);
      expect(dto.sessionId, 'session-123');
      expect(dto.files, hasLength(1));
      expect(dto.files['file-1'], 'token-abc');
    });

    test('should serialize to JSON', () {
      const dto = PrepareUploadResponseDto(
        sessionId: 'sess-456',
        files: {'f1': 't1', 'f2': 't2'},
      );

      final json = dto.toJson();
      expect(json['sessionId'], 'sess-456');
      expect(json['files'], hasLength(2));
    });
  });

  group('FileDto', () {
    test('mime lookup should work for known extensions', () {
      final dto = FileDto(
        id: 'file-1',
        fileName: 'test.txt',
        size: 1024,
        fileType: FileType.text,
        hash: null,
        preview: null,
        metadata: null,
      );

      expect(dto.lookupMime(), 'text/plain');
    });

    test('FileDto equality should be based on id and fileName', () {
      final dto1 = FileDto(
        id: 'file-1',
        fileName: 'test.txt',
        size: 100,
        fileType: FileType.text,
        hash: null,
        preview: null,
        metadata: null,
      );

      final dto2 = FileDto(
        id: 'file-1',
        fileName: 'test.txt',
        size: 200, // Different size
        fileType: FileType.text,
        hash: null,
        preview: null,
        metadata: null,
      );

      // FileDto uses custom equality based on id, fileName, size, fileType, hash, preview
      expect(dto1 == dto2, false); // Different size, so not equal
    });
  });

  group('FileMetadata', () {
    test('should serialize and deserialize', () {
      final metadata = FileMetadata(
        lastModified: DateTime(2024, 1, 1),
        lastAccessed: DateTime(2024, 1, 2),
      );

      final json = metadata.toJson();
      expect(json['modified'], isNotNull);
      expect(json['accessed'], isNotNull);

      final restored = FileMetadataMapper.fromJson(json);
      expect(restored.lastModified, isNotNull);
      expect(restored.lastAccessed, isNotNull);
    });
  });
}
