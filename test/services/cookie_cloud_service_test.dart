import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:pt_mate/services/network/cookie_cloud_service.dart';
import 'package:pt_mate/services/site_config_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/utils/backup_migrators.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late CookieCloudService service;
  final Map<String, String> secureStorage = {};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PT Mate',
      packageName: 'com.github.justlookatnow.ptmate',
      version: '1.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
    secureStorage.clear();
    SiteConfigService.clearAllCache();
    StorageService.instance.resetForTest();
    service = CookieCloudService();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'write':
              secureStorage[methodCall.arguments['key'] as String] =
                  methodCall.arguments['value'] as String;
              return null;
            case 'read':
              return secureStorage[methodCall.arguments['key'] as String];
            case 'delete':
              secureStorage.remove(methodCall.arguments['key'] as String);
              return null;
            case 'containsKey':
              return secureStorage.containsKey(
                methodCall.arguments['key'] as String,
              );
            case 'readAll':
              return Map<String, String>.from(secureStorage);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decryptPayload should decode salted base64 payload', () {
    const uuid = 'uuid-1234';
    const password = 'secret-pass';
    const plainText = '{"example.org":"sid=abc; token=xyz"}';
    final encrypted = _encryptSalted(
      plainText,
      uuid: uuid,
      password: password,
      salt: Uint8List.fromList(List<int>.generate(8, (index) => index + 1)),
    );

    final decrypted = CookieCloudService.decryptPayload(
      encrypted,
      uuid: uuid,
      password: password,
    );

    expect(decrypted, plainText);
  });

  test('buildSyncPlan should classify update/addition/unknown', () async {
    await StorageService.instance.saveSiteConfigs([
      const SiteConfig(
        id: 'local-site',
        name: 'Local Site',
        baseUrl: 'https://local.example.org',
        cookie: 'sid=old',
        siteType: SiteType.nexusphpweb,
      ),
    ]);

    final templates = await SiteConfigService.loadPresetSiteTemplates();
    final template = templates.firstWhere(
      (item) =>
          item.baseUrls.isNotEmpty && item.siteType == SiteType.nexusphpweb,
      orElse: () => throw StateError('No NexusPHPWeb template available'),
    );
    final templateHost = Uri.parse(template.baseUrls.first).host;

    final plan = await service.buildSyncPlan({
      'local.example.org': 'sid=new',
      templateHost: 'tid=123',
      'unknown.example.net': 'uid=777',
    });

    expect(plan.updates, hasLength(1));
    expect(plan.updates.first.site?.id, 'local-site');
    expect(plan.additions, hasLength(1));
    expect(plan.additions.first.template?.id, template.id);
    expect(plan.unknown, hasLength(1));
    expect(plan.unknown.first.host, 'unknown.example.net');
  });

  test('buildSyncPlan should skip NexusPHP api sites like PTSKit', () async {
    await StorageService.instance.saveSiteConfigs([
      const SiteConfig(
        id: 'ptskit',
        name: 'PTSKit',
        baseUrl: 'https://www.ptskit.org/',
        cookie: 'sid=old',
        siteType: SiteType.nexusphp,
        templateId: 'ptskit',
      ),
    ]);

    final plan = await service.buildSyncPlan({
      '.www.ptskit.org': 'sid=dot-www',
      'www.ptskit.org': 'sid=www',
      'ptskit.org': 'sid=root',
    });

    expect(plan.updates, isEmpty);
    expect(plan.additions, isEmpty);
    expect(plan.unknown, isEmpty);
  });

  test('buildSyncPlan should merge parent and exact host cookies', () async {
    await StorageService.instance.saveSiteConfigs([
      const SiteConfig(
        id: 'hddolby',
        name: 'HDDolby',
        baseUrl: 'https://www.hddolby.com/',
        cookie: 'old=1',
        siteType: SiteType.nexusphpweb,
        templateId: 'hddolby',
      ),
    ]);

    final plan = await service.buildSyncPlan({
      '.hddolby.com': 'parent=1; same=parent',
      'hddolby.com': 'root=1',
      'www.hddolby.com': 'same=exact; exact=1',
    });

    expect(plan.updates, hasLength(1));
    expect(plan.additions, isEmpty);
    expect(plan.unknown, isEmpty);
    expect(plan.updates.first.host, 'www.hddolby.com');
    expect(_cookieMap(plan.updates.first.cookie), {
      'parent': '1',
      'same': 'exact',
      'root': '1',
      'exact': '1',
    });
  });

  test('buildSyncPlan should recommend Gazelle templates', () async {
    final templates = await SiteConfigService.loadPresetSiteTemplates();
    final template = templates.firstWhere(
      (item) => item.baseUrls.isNotEmpty && item.siteType == SiteType.gazelle,
      orElse: () => throw StateError('No Gazelle template available'),
    );
    final host = Uri.parse(template.baseUrls.first).host;

    final plan = await service.buildSyncPlan({host: 'session=abc'});

    expect(plan.updates, isEmpty);
    expect(plan.additions, hasLength(1));
    expect(plan.additions.first.template?.id, template.id);
    expect(plan.unknown, isEmpty);
  });

  test(
    'save and load cookie cloud config should persist secure password',
    () async {
      await StorageService.instance.saveCookieCloudConfig(
        const CookieCloudConfig(
          url: 'https://cookie.example.com',
          uuid: 'uuid-1',
          password: 'pwd-1',
          autoSyncEnabled: true,
          syncIntervalMinutes: 120,
        ),
      );

      final loaded = await StorageService.instance.loadCookieCloudConfig();
      expect(loaded.url, 'https://cookie.example.com');
      expect(loaded.uuid, 'uuid-1');
      expect(loaded.password, 'pwd-1');
      expect(loaded.autoSyncEnabled, isTrue);
      expect(loaded.syncIntervalMinutes, 120);
    },
  );

  test('BackupService should export and restore CookieCloudConfig', () async {
    final storage = StorageService.instance;
    await storage.saveCookieCloudConfig(
      const CookieCloudConfig(
        url: 'https://backup-test.cloud',
        uuid: 'uuid-backup',
        password: 'pass-backup',
        autoSyncEnabled: true,
        syncIntervalMinutes: 180,
        lastSyncSummary: 'Success-backup',
      ),
    );

    final backupService = BackupService(storage);
    final backupData = await backupService.createBackup();

    expect(backupData.version, '1.3.0');
    expect(backupData.data.containsKey('cookieCloudConfig'), isTrue);

    final exportedJson =
        backupData.data['cookieCloudConfig'] as Map<String, dynamic>;
    expect(exportedJson['url'], 'https://backup-test.cloud');
    expect(exportedJson['uuid'], 'uuid-backup');
    expect(exportedJson['password'], 'pass-backup');
    expect(exportedJson['autoSyncEnabled'], isTrue);
    expect(exportedJson['syncIntervalMinutes'], 180);
    expect(exportedJson['lastSyncSummary'], 'Success-backup');

    // 清空当前存储，用于测试恢复
    storage.resetForTest();

    final restoreResult = await backupService.restoreBackup(backupData);
    expect(restoreResult.success, isTrue);

    final restored = await storage.loadCookieCloudConfig();
    expect(restored.url, 'https://backup-test.cloud');
    expect(restored.uuid, 'uuid-backup');
    expect(restored.password, 'pass-backup');
    expect(restored.autoSyncEnabled, isTrue);
    expect(restored.syncIntervalMinutes, 180);
    expect(restored.lastSyncSummary, 'Success-backup');
  });

  test('BackupMigrationManager should migrate v1.2.0 to v1.3.0 gracefully',
      () async {
    final legacyBackup = {
      'version': '1.2.0',
      'timestamp': DateTime.now().toIso8601String(),
      'appVersion': '1.0.0',
      'data': {
        'siteConfigs': [],
        'activeSiteId': null,
        'downloaderConfigs': [],
        'defaultDownloaderId': null,
        'downloaderPasswords': {},
        'userPreferences': {},
        'downloaderCategoriesCache': {},
        'downloaderTagsCache': {},
        'aggregateSearchSettings': {
          'shortcutType': 'none',
          'searchTimeout': 15,
          'aggregateSearchConfigs': [],
        },
      },
    };

    final migrated = BackupMigrationManager.migrate(legacyBackup, '1.3.0');
    expect(migrated['version'], '1.3.0');
    expect(migrated['data']['cookieCloudConfig'], isNull); // 1.2.0 备份中不包含此字段，完美兼容
  });
}

Map<String, String> _cookieMap(String cookie) {
  final result = <String, String>{};
  for (final part in cookie.split(';')) {
    final trimmed = part.trim();
    final index = trimmed.indexOf('=');
    if (index <= 0) continue;
    result[trimmed.substring(0, index)] = trimmed.substring(index + 1);
  }
  return result;
}

String _encryptSalted(
  String plainText, {
  required String uuid,
  required String password,
  required Uint8List salt,
}) {
  final keySeed = crypto.md5
      .convert(utf8.encode('$uuid-$password'))
      .toString()
      .substring(0, 16);
  final keyIv = CookieCloudService.deriveOpenSslKeyIv(
    utf8.encode(keySeed),
    salt,
    keyLength: 32,
    ivLength: 16,
  );
  final key = encrypt.Key(Uint8List.fromList(keyIv.sublist(0, 32)));
  final iv = encrypt.IV(Uint8List.fromList(keyIv.sublist(32, 48)));
  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );
  final encrypted = encrypter.encrypt(plainText, iv: iv).bytes;
  return base64Encode([...utf8.encode('Salted__'), ...salt, ...encrypted]);
}
