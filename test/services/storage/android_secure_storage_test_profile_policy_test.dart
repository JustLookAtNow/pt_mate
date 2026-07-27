import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gradle 仅为合法 debug profile 生成独立 applicationId', () {
    final source = File('android/app/build.gradle.kts').readAsStringSync();

    for (final profile in ['oaepGcm', 'pkcs1Gcm', 'pkcs1Cbc']) {
      expect(source, contains('"$profile" to ".securestoragetest.'));
    }
    expect(source, contains('gradleProperty("secureStorageTestProfile")'));
    expect(source, contains('secureStorageTestProfile !in'));
    expect(
      source,
      contains('applicationIdSuffix = secureStorageTestApplicationIdSuffix'),
    );
  });

  test('隔离 profile 构建脚本逐份验证并保存唯一 APK', () {
    final source = File(
      'tool/build_secure_storage_test_apks.sh',
    ).readAsStringSync();

    expect(source, contains('flock 9'));
    expect(source, contains(r'secureStorageTestProfile=$profile'));
    expect(source, contains('apkanalyzer_bin" manifest application-id'));
    expect(source, contains('apkanalyzer_bin" manifest version-code'));
    expect(source, contains('refusing to preserve production applicationId'));
    expect(source, contains(r'verify_apk "$shared_apk_path" "$profile"'));
    expect(source, contains(r'verify_apk "$artifact_path" "$profile"'));
    expect(
      source,
      contains(
        r'ptmate-secure-storage-${profile}-debug-${candidate_build}.apk',
      ),
    );
    expect(source, contains('ENABLE_SECURE_STORAGE_TRANSACTIONS=false'));
    expect(source, contains('ENABLE_SECURE_STORAGE_TRANSACTIONS=true'));
  });

  test('release BuildConfig 强制清空测试 profile 与后缀', () {
    final source = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseBlock = RegExp(
      r'release\s*\{(.*?)\n\s*\}',
      dotAll: true,
    ).firstMatch(source)?.group(1);

    expect(releaseBlock, isNotNull);
    expect(
      releaseBlock,
      contains(
        r'buildConfigField("String", "SECURE_STORAGE_TEST_PROFILE", "\"\"")',
      ),
    );
    expect(
      releaseBlock,
      contains(
        r'buildConfigField("String", "SECURE_STORAGE_TEST_APPLICATION_ID_SUFFIX", "\"\"")',
      ),
    );
  });

  test('原生 bootstrap 同时要求 debug、测试后缀和真实 fresh 状态', () {
    final source = File(
      'android/app/src/main/kotlin/com/github/justlookatnow/ptmate/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('if (!BuildConfig.DEBUG) return false'));
    expect(source, contains('configuredSuffix.isNotBlank()'));
    expect(
      source,
      contains(
        'configuredSuffix.startsWith(SECURE_STORAGE_TEST_SUFFIX_PREFIX)',
      ),
    );
    expect(
      source,
      contains('BuildConfig.APPLICATION_ID.endsWith(configuredSuffix)'),
    );
    expect(source, contains('before.status != "fresh"'));
    expect(source, contains('before.profile != "fresh"'));
    expect(source, contains('before.hasEncryptedEntries'));
    expect(source, contains('before.hasWrappedKeys'));
    expect(
      source,
      contains('.putBoolean(ENCRYPTED_PREFERENCES_MIGRATED_MARKER, true)'),
    );
    expect(source, contains('.commit()'));
    expect(source, isNot(contains('applySecureStorageTestProfileOverride')));
  });
}
