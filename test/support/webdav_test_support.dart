import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/services/webdav_service.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

const webdavSSLMessage = 'SSL证书验证失败，请检查HTTPS配置';

DioException webdavHttpError(int status) {
  final options = RequestOptions(path: '/PTMate/backups');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status),
  );
}

class FakeWebDAVClient implements webdav.Client {
  Future<List<webdav.File>> Function(String path)? onReadDir;
  Future<List<int>> Function(String path)? onRead;
  Future<void> Function(String path)? onMkdir;
  Future<void> Function(String path)? onWrite;
  final createdDirectories = <String>[];
  final uploads = <String, List<int>>{};
  List<webdav.File> files = [];

  @override
  void setConnectTimeout(int timeout) {}

  @override
  void setSendTimeout(int timeout) {}

  @override
  void setReceiveTimeout(int timeout) {}

  @override
  Future<List<webdav.File>> readDir(
    String path, [
    CancelToken? cancelToken,
  ]) async => onReadDir == null ? files : await onReadDir!(path);

  @override
  Future<List<int>> read(
    String path, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async => onRead == null
      ? utf8.encode(
          jsonEncode({
            'version': BackupVersion.current,
            'timestamp': '2026-10-23T12:00:00.000',
            'appVersion': '2.29.5',
            'data': <String, dynamic>{},
          }),
        )
      : await onRead!(path);

  @override
  Future<void> mkdir(String path, [CancelToken? cancelToken]) async {
    createdDirectories.add(path);
    await onMkdir?.call(path);
  }

  @override
  Future<void> write(
    String path,
    Uint8List data, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await onWrite?.call(path);
    uploads[path] = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class WebDAVTestHarness {
  static const config = WebDAVConfig(
    id: 'webdav-test',
    name: 'Test',
    serverUrl: 'https://dav.example.org',
    username: 'user',
    remotePath: '/PTMate/backups',
    isEnabled: true,
  );
  static const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final storage = StorageService.instance;
  final webdavService = WebDAVService.instance;
  final client = FakeWebDAVClient();
  final secureValues = <String, String>{};
  bool failSecureWrites = false;
  Future<void> Function()? beforeSecureWrite;

  Future<void> setUp({bool configured = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    webdavService.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'PT Mate',
      packageName: 'pt_mate',
      version: '2.29.5',
      buildNumber: '193',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final key = call.arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              return secureValues[key];
            case 'write':
              await beforeSecureWrite?.call();
              if (failSecureWrites) {
                throw PlatformException(code: 'test_write_failure');
              }
              secureValues[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              secureValues.remove(key);
              return null;
            case 'containsKey':
              return secureValues.containsKey(key);
            case 'readAll':
              return Map<String, String>.from(secureValues);
            default:
              return null;
          }
        });
    await storage.initializeSecureStorage();
    if (configured) {
      await webdavService.saveConfig(config, password: 'password');
    }
    webdavService.overrideClientFactoryForTest((_, _) => client);
  }

  Future<void> tearDown() async {
    NotificationHelper.resetForTest();
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    webdavService.resetForTest();
    storage.resetForTest();
  }
}
