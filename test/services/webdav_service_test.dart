import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../support/webdav_test_support.dart';

class _RecordingFilePicker extends FilePickerPlatform {
  int saveCount = 0;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saveCount++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebDAVTestHarness harness;

  setUp(() async {
    harness = WebDAVTestHarness();
    await harness.setUp();
  });
  tearDown(() => harness.tearDown());

  final options = RequestOptions(path: '/');
  final failures = <String, (Object, String)>{
    'Dio certificate': (
      DioException(
        requestOptions: options,
        type: DioExceptionType.badCertificate,
      ),
      webdavSSLMessage,
    ),
    'wrapped TLS handshake': (
      DioException(
        requestOptions: options,
        error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      ),
      webdavSSLMessage,
    ),
    'native TLS': (const TlsException('TLS failure'), webdavSSLMessage),
    'uppercase certificate': (
      Exception('CERTIFICATE_VERIFY_FAILED'),
      webdavSSLMessage,
    ),
    'timeout': (
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      ),
      '连接超时',
    ),
    'unauthorized': (webdavHttpError(401), '用户名或密码错误'),
  };

  for (final entry in failures.entries) {
    test(
      '${entry.key} is reported by connection, upload and downloads',
      () async {
        final (error, message) = entry.value;
        harness.client.onReadDir = (_) async => throw error;
        harness.client.onRead = (_) async => throw error;

        final result = await harness.webdavService.testConnection();
        expect(result.success, isFalse);
        expect(result.errorMessage, contains(message));
        final service = harness.webdavService;
        final operations = <Future<Object?> Function()>[
          service.getRemoteBackups,
          service.downloadLatestBackup,
          () => service.downloadBackup('/backup.json'),
          () async {
            await service.uploadBackup('{}');
            return null;
          },
        ];
        for (final operation in operations) {
          await expectLater(
            operation(),
            throwsA(
              predicate<Object>((error) => error.toString().contains(message)),
            ),
          );
        }
        expect(harness.client.createdDirectories, isEmpty);
        expect(harness.client.uploads, isEmpty);
        expect(await service.getLastSyncTime(), isNull);
      },
    );
  }

  test('successful empty directory is the only empty backup result', () async {
    expect(await harness.webdavService.getRemoteBackups(), isEmpty);
    expect(await harness.webdavService.downloadLatestBackup(), isNull);
  });

  test('lists backups newest first and downloads valid content', () async {
    harness.client.files = [
      webdav.File(name: 'old.json', mTime: DateTime(2025)),
      webdav.File(name: 'ignore.txt'),
      webdav.File(name: 'new.json', mTime: DateTime(2026)),
    ];
    final backups = await harness.webdavService.getRemoteBackups();
    expect(backups.map((file) => file['name']), ['new.json', 'old.json']);
    final backupService = BackupService(harness.storage);
    expect(
      await backupService.downloadWebDAVBackup(backups.first['path']),
      isNotNull,
    );
    expect(await backupService.importBackupFromWebDAV(), isNotNull);
  });

  test('upload succeeds and records last sync only after writing', () async {
    final result = await BackupService(harness.storage)
        .exportBackupWithWebDAV();
    expect(result, 'WebDAV云端备份');
    expect(harness.client.uploads, hasLength(1));
    final backup = jsonDecode(
      utf8.decode(harness.client.uploads.values.single),
    );
    expect(backup['version'], BackupVersion.current);
    expect(await harness.webdavService.getLastSyncTime(), isNotNull);
  });

  test('missing parent directories are created recursively', () async {
    harness.client.onReadDir = (_) async => throw webdavHttpError(404);
    var first = true;
    harness.client.onMkdir = (_) async {
      if (first) {
        first = false;
        throw webdavHttpError(409);
      }
    };
    await harness.webdavService.uploadBackup('{}', filename: 'backup.json');
    expect(harness.client.createdDirectories, [
      '/PTMate/backups',
      '/PTMate',
      '/PTMate/backups',
    ]);
    expect(harness.client.uploads, contains('/PTMate/backups/backup.json'));
  });

  test('directory creation failure aborts upload', () async {
    harness.client.onReadDir = (_) async => throw webdavHttpError(404);
    harness.client.onMkdir = (_) async => throw webdavHttpError(403);
    await expectLater(
      harness.webdavService.uploadBackup('{}'),
      throwsA(predicate<Object>((e) => e.toString().contains('权限'))),
    );
    expect(harness.client.createdDirectories, hasLength(1));
    expect(harness.client.uploads, isEmpty);
  });

  test('mobile upload failure never opens a local file picker', () async {
    final originalPicker = FilePickerPlatform.instance;
    final picker = _RecordingFilePicker();
    FilePickerPlatform.instance = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      FilePickerPlatform.instance = originalPicker;
      debugDefaultTargetPlatformOverride = null;
    });
    harness.client.onWrite = (_) async => throw const HandshakeException();
    await expectLater(
      BackupService(harness.storage).exportBackupWithWebDAV(),
      throwsA(
        isA<BackupException>().having(
          (error) => error.message,
          'message',
          contains(webdavSSLMessage),
        ),
      ),
    );
    expect(picker.saveCount, 0);
    expect(await harness.webdavService.getLastSyncTime(), isNull);
  });
}
