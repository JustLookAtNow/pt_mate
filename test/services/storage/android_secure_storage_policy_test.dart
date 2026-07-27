import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/storage/storage_service.dart';

void main() {
  test('所有 AndroidOptions 显式关闭自动 reset 与静默迁移', () {
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    final constructors = RegExp(
      r'AndroidOptions(?:\.[A-Za-z_]\w*)?\((.*?)\);',
      dotAll: true,
    ).allMatches(dartSources);

    expect(constructors, isNotEmpty);
    expect(
      RegExp(
        r'AndroidOptions(?:\.[A-Za-z_]\w*)?\((.*?)\);',
        dotAll: true,
      ).hasMatch('const options = AndroidOptions.biometric();'),
      isTrue,
    );
    for (final constructor in constructors) {
      final body = constructor.group(1)!;
      expect(body, contains('resetOnError: false'));
      expect(body, contains('migrateOnAlgorithmChange: false'));
      expect(body, contains('migrateWithBackup: false'));
    }
    expect(dartSources, isNot(contains('resetOnError: true')));
    expect(dartSources, isNot(contains('deleteAll(')));
  });

  test('第二阶段事务默认关闭且只能由显式构建参数开启', () {
    final source = File(
      'lib/services/storage/storage_service.dart',
    ).readAsStringSync();
    final releaseWorkflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    final gate = RegExp(
      r"bool\.fromEnvironment\(\s*'ENABLE_SECURE_STORAGE_TRANSACTIONS',(.*?)\);",
      dotAll: true,
    ).firstMatch(source)?.group(1);

    expect(gate, isNotNull);
    expect(gate, contains('defaultValue: false'));
    expect(releaseWorkflow, contains('secure_storage_transactions:'));
    expect(releaseWorkflow, contains('default: false'));
    expect(
      releaseWorkflow,
      contains('--dart-define=ENABLE_SECURE_STORAGE_TRANSACTIONS='),
    );
  });

  test('全新 Android marker 初始化必须由只读探测守卫并同步提交', () {
    final source = File(
      'android/app/src/main/kotlin/com/github/justlookatnow/ptmate/MainActivity.kt',
    ).readAsStringSync();
    final start = source.indexOf(
      'private fun initializeFreshAndroidSecureStorage()',
    );
    final end = source.indexOf('\n    /**', start);

    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final initializer = source.substring(start, end);
    expect(initializer, contains('before.status != "fresh"'));
    expect(initializer, contains('before.hasEncryptedEntries'));
    expect(initializer, contains('before.hasWrappedKeys'));
    expect(
      initializer,
      contains('SecureStorageProbeClassifier.KEY_CIPHER_OAEP'),
    );
    expect(
      initializer,
      contains('SecureStorageProbeClassifier.STORAGE_CIPHER_GCM'),
    );
    expect(initializer, contains('.commit()'));
    expect(initializer, isNot(contains('.apply()')));
    expect(initializer, contains('fresh_initialization_rejected'));
    expect(initializer, contains('fresh_initialization_verification_failed'));
    expect(initializer, isNot(contains('delete')));

    final probeStart = source.indexOf(
      'private fun readSecureStorageProbeInput()',
    );
    final probeEnd = source.indexOf(
      'private fun validateSecureStorageTestProfile',
      probeStart,
    );
    final probe = source.substring(probeStart, probeEnd);
    expect(probe, contains('dataEntries.isNotEmpty()'));
    expect(probe, contains('wrappedKeyEntries.isNotEmpty()'));
    expect(probe, isNot(contains('dataEntries.keys.any')));
    expect(probe, isNot(contains('wrappedKeyEntries.keys.any')));
    expect(probe, contains('hasFlutterSharedPreferencesFile()'));
    expect(probe, isNot(contains('ordinaryPreferences')));
    expect(
      probe,
      isNot(contains('FLUTTER_SHARED_PREFERENCES, Context.MODE_PRIVATE')),
    );
    expect(probe, isNot(contains('ENCRYPTED_ENTRIES_EXPECTED_KEY')));
    expect(probe, isNot(contains('SENSITIVE_TRANSACTION_MANIFEST_KEY')));
    expect(probe, isNot(contains('hasExistingAppData')));
    expect(source, contains('File(applicationInfo.dataDir, "shared_prefs")'));
    expect(source, contains(r'"$FLUTTER_SHARED_PREFERENCES.xml"'));
    expect(source, contains(r'"$FLUTTER_SHARED_PREFERENCES.xml.bak"'));
  });

  test('事务切换 manifest 前必须经过 Android 同步落盘屏障', () {
    final nativeSource = File(
      'android/app/src/main/kotlin/com/github/justlookatnow/ptmate/MainActivity.kt',
    ).readAsStringSync();
    final transactionSource = File(
      'lib/services/storage/secure_storage_transaction.dart',
    ).readAsStringSync();
    final storageSource = File(
      'lib/services/storage/storage_service.dart',
    ).readAsStringSync();
    final start = nativeSource.indexOf(
      'private fun flushAndroidSecureStorage()',
    );
    final end = nativeSource.indexOf(
      'private fun readSecureStorageProbeInput()',
      start,
    );

    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final barrier = nativeSource.substring(start, end);
    for (final preference in [
      'SECURE_STORAGE_LEGACY_CONFIG_PREFS',
      'SECURE_STORAGE_NAMESPACED_CONFIG_PREFS',
      'SECURE_STORAGE_KEY_PREFS',
      'SECURE_STORAGE_DATA_PREFS',
    ]) {
      expect(barrier, contains(preference));
    }
    expect(barrier, contains('.commit()'));
    expect(barrier, isNot(contains('.apply()')));
    expect(nativeSource, contains('"flushAndroidSecureStorage"'));

    final barrierCall = transactionSource.indexOf(
      '_beforeManifestBarrier?.call(revision)',
    );
    final preparationCall = transactionSource.indexOf(
      'beforeManifestCommit?.call(revision)',
    );
    final manifestWrite = transactionSource.indexOf(
      '_writeManifest(manifestPreferenceKey, encodedManifest)',
    );
    expect(barrierCall, isNonNegative);
    expect(preparationCall, greaterThan(barrierCall));
    expect(manifestWrite, greaterThan(preparationCall));
    expect(storageSource, contains('beforeManifestBarrier:'));
    expect(
      storageSource,
      contains('_flushAndroidSecureStorageDurabilityBarrier()'),
    );
  });

  test('Manifest 与两套规则禁止备份全部安全存储文件', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final legacyRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modernRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, isNot(contains('ALLOW_BACKUP')));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(modernRules, contains('<cloud-backup>'));
    expect(modernRules, contains('<device-transfer>'));
    const excludeAllPreferences = '<exclude domain="sharedpref" path="." />';
    expect(legacyRules.split(excludeAllPreferences).length - 1, 1);
    expect(modernRules.split(excludeAllPreferences).length - 1, 2);
  });

  test('Android profile 解析后不存在 OAEP 默认选项回退', () {
    final source = File(
      'lib/services/storage/storage_service.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<AndroidOptions> _getAndroidSecureOptions()',
    );
    final end = source.indexOf(
      'Future<SecureReadResult<String>> _secureReadResult',
      start,
    );
    final method = source.substring(start, end);

    expect(method, contains('secure_storage_options_unavailable'));
    expect(method, isNot(contains('?? _androidModernSecureOptions')));
  });

  test('安全存储异常文本只暴露类别而不包含 cause', () {
    const exception = SecureStorageUnavailableException(
      'timeout',
      'site-id and secret-value',
    );
    expect(exception.toString(), 'SecureStorageUnavailableException(timeout)');
    expect(exception.toString(), isNot(contains('site-id')));
    expect(exception.toString(), isNot(contains('secret-value')));
  });

  test('Release 日志路径不采集任意异常、堆栈、print 或 HTML', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final storageSource = File(
      'lib/services/storage/storage_service.dart',
    ).readAsStringSync();
    final adapterSource = File(
      'lib/services/api/nexusphp_web_adapter.dart',
    ).readAsStringSync();
    final gradleSource = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final proguardSource = File(
      'android/app/proguard-rules.pro',
    ).readAsStringSync();

    expect(mainSource, contains('if (!kIsWeb && kDebugMode)'));
    expect(mainSource, contains('if (kDebugMode) {'));
    expect(mainSource, contains('Application error category=uncaught'));
    expect(adapterSource, contains('if (!kDebugMode) return;'));
    expect(gradleSource, contains('isMinifyEnabled = true'));
    expect(gradleSource, contains('"proguard-rules.pro"'));
    for (final level in ['v', 'd', 'i', 'w', 'e', 'wtf']) {
      expect(proguardSource, contains('public static int $level(...);'));
    }

    final auditStart = storageSource.indexOf('final auditLine');
    final auditEnd = storageSource.indexOf(
      'LogFileService.instance.append(auditLine)',
      auditStart,
    );
    expect(auditStart, isNonNegative);
    expect(auditEnd, greaterThan(auditStart));
    final auditBlock = storageSource.substring(auditStart, auditEnd);
    expect(auditBlock, contains('profile='));
    expect(auditBlock, contains('state='));
    expect(auditBlock, contains('code='));
    expect(auditBlock, isNot(contains('platform=')));
    expect(auditBlock, isNot(contains(r'$error')));
    expect(auditBlock, isNot(contains('siteId')));
    expect(auditBlock, isNot(contains('key')));
  });
}
