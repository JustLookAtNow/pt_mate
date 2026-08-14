import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pt_mate/secure_storage_profile');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses every supported profile', () async {
    final cases =
        <
          ({
            String name,
            AndroidSecureStorageProfile profile,
            String keyCipher,
            String storageCipher,
          })
        >[
          (
            name: 'oaepGcm',
            profile: AndroidSecureStorageProfile.oaepGcm,
            keyCipher: 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
            storageCipher: 'AES_GCM_NoPadding',
          ),
          (
            name: 'pkcs1Gcm',
            profile: AndroidSecureStorageProfile.pkcs1Gcm,
            keyCipher: 'RSA_ECB_PKCS1Padding',
            storageCipher: 'AES_GCM_NoPadding',
          ),
          (
            name: 'pkcs1Cbc',
            profile: AndroidSecureStorageProfile.pkcs1Cbc,
            keyCipher: 'RSA_ECB_PKCS1Padding',
            storageCipher: 'AES_CBC_PKCS7Padding',
          ),
        ];

    for (final entry in cases) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probeAndroidSecureStorage');
            return <String, Object?>{
              'status': 'ready',
              'profile': entry.name,
              'keyCipher': entry.keyCipher,
              'storageCipher': entry.storageCipher,
              'hasEncryptedEntries': true,
              'hasWrappedKeys': true,
              'failureCode': null,
            };
          });

      final result = await AndroidSecureStorageProfileResolver(
        channel: channel,
        isAndroid: true,
      ).probe();

      expect(result.profile, entry.profile);
      expect(
        result.isReady,
        entry.profile == AndroidSecureStorageProfile.oaepGcm,
      );
      expect(result.hasEncryptedEntries, isTrue);
      expect(result.hasWrappedKeys, isTrue);
    }
  });

  test('parses fresh storage without claiming encrypted data', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'status': 'fresh',
            'profile': 'fresh',
            'keyCipher': null,
            'storageCipher': null,
            'hasEncryptedEntries': false,
            'hasWrappedKeys': false,
            'failureCode': null,
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.fresh);
    expect(result.isReady, isTrue);
  });

  test('parses the permanent Android plaintext profile', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'status': 'ready',
            'profile': 'plaintext',
            'keyCipher': null,
            'storageCipher': null,
            'hasEncryptedEntries': false,
            'hasWrappedKeys': false,
            'failureCode': null,
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.plaintext);
    expect(result.isReady, isTrue);
  });

  test(
    'only explicit unsupported_algorithm permits plaintext fallback',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probeModernSecureStorageCapability');
            return <String, Object?>{
              'status': 'unsupported',
              'failureCode': 'unsupported_algorithm',
            };
          });

      final result = await AndroidSecureStorageProfileResolver(
        channel: channel,
        isAndroid: true,
      ).probeModernCapability();

      expect(result.isSupported, isFalse);
      expect(result.isExplicitlyUnsupported, isTrue);
      expect(result.failureCode, 'unsupported_algorithm');
    },
  );

  test('capability probe transient errors remain fail-closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'probeModernSecureStorageCapability');
          return <String, Object?>{
            'status': 'unavailable',
            'failureCode': 'capability_probe_failed',
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probeModernCapability();

    expect(result.isSupported, isFalse);
    expect(result.isExplicitlyUnsupported, isFalse);
    expect(result.failureCode, 'capability_probe_failed');
  });

  test('legacy reset requires confirmation and native fresh result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'resetLegacyAndroidSecureStorage');
          expect(call.arguments, <String, Object?>{'confirmed': true});
          return <String, Object?>{'status': 'fresh', 'failureCode': null};
        });
    final resolver = AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    );

    expect(await resolver.resetLegacyStorage(confirmed: false), isFalse);
    expect(await resolver.resetLegacyStorage(confirmed: true), isTrue);
  });

  test(
    'initializes a fresh namespace only through the dedicated method',
    () async {
      final invokedMethods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invokedMethods.add(call.method);
            expect(call.method, 'initializeFreshAndroidSecureStorage');
            return <String, Object?>{
              'status': 'ready',
              'profile': 'oaepGcm',
              'keyCipher': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
              'storageCipher': 'AES_GCM_NoPadding',
              'hasEncryptedEntries': false,
              'hasWrappedKeys': false,
              'failureCode': null,
            };
          });

      final result = await AndroidSecureStorageProfileResolver(
        channel: channel,
        isAndroid: true,
      ).initializeFreshOaepGcm();

      expect(invokedMethods, <String>['initializeFreshAndroidSecureStorage']);
      expect(result.profile, AndroidSecureStorageProfile.oaepGcm);
      expect(result.isReady, isTrue);
      expect(result.hasEncryptedEntries, isFalse);
      expect(result.hasWrappedKeys, isFalse);
    },
  );

  test('preserves a rejected fresh initialization as unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'initializeFreshAndroidSecureStorage');
          return <String, Object?>{
            'status': 'inconsistent',
            'profile': 'inconsistent',
            'keyCipher': null,
            'storageCipher': null,
            'hasEncryptedEntries': true,
            'hasWrappedKeys': false,
            'failureCode': 'fresh_initialization_rejected',
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).initializeFreshOaepGcm();

    expect(result.isReady, isFalse);
    expect(result.failureCode, 'fresh_initialization_rejected');
  });

  test('preserves a non-sensitive native failure code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'status': 'inconsistent',
            'profile': 'inconsistent',
            'keyCipher': null,
            'storageCipher': null,
            'hasEncryptedEntries': true,
            'hasWrappedKeys': false,
            'failureCode': 'missing_wrapped_key',
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.inconsistent);
    expect(result.isReady, isFalse);
    expect(result.failureCode, 'missing_wrapped_key');
  });

  test('rejects malformed or contradictory native results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'status': 'fresh',
            'profile': 'oaepGcm',
            'hasEncryptedEntries': true,
            'hasWrappedKeys': true,
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.inconsistent);
    expect(result.failureCode, 'invalid_probe_result');
  });

  test('rejects a ready profile whose algorithms do not match', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'status': 'ready',
            'profile': 'oaepGcm',
            'keyCipher': 'RSA_ECB_PKCS1Padding',
            'storageCipher': 'AES_GCM_NoPadding',
            'hasEncryptedEntries': true,
            'hasWrappedKeys': true,
            'failureCode': null,
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.inconsistent);
    expect(result.failureCode, 'invalid_probe_result');
  });

  test('does not invoke Android channel on other platforms', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          invoked = true;
          return null;
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: false,
    ).probe();

    expect(invoked, isFalse);
    expect(result.profile, AndroidSecureStorageProfile.unsupported);
    expect(result.failureCode, 'not_android');
  });

  test('accepts a successful native durability flush barrier', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'flushAndroidSecureStorage');
          return <String, Object?>{'status': 'ready', 'failureCode': null};
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).flush();

    expect(result.isSuccessful, isTrue);
    expect(result.failureCode, isNull);
  });

  test('preserves a native durability flush failure category', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'flushAndroidSecureStorage');
          return <String, Object?>{
            'status': 'unavailable',
            'failureCode': 'secure_storage_flush_commit_failed',
          };
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).flush();

    expect(result.isSuccessful, isFalse);
    expect(result.failureCode, 'secure_storage_flush_commit_failed');
  });

  test('converts a stalled native durability flush to unavailable', () async {
    final flushChannel = MethodChannel(
      'pt_mate/secure_storage_flush_timeout_'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          flushChannel,
          (_) => Completer<Object?>().future,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(flushChannel, null),
    );

    final result = await AndroidSecureStorageProfileResolver(
      channel: flushChannel,
      isAndroid: true,
      probeTimeout: const Duration(milliseconds: 10),
    ).flush();

    expect(result.isSuccessful, isFalse);
    expect(result.failureCode, 'native_flush_timeout');
  });

  test('converts platform failures to an unavailable result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'probe_failed', message: 'ignored');
        });

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.inconsistent);
    expect(result.failureCode, 'native_probe_failed');
  });

  test('converts a stalled native probe to an unavailable result', () async {
    final channel = MethodChannel(
      'pt_mate/secure_storage_profile_timeout_${DateTime.now().microsecondsSinceEpoch}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => Completer<Object?>().future);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await AndroidSecureStorageProfileResolver(
      channel: channel,
      isAndroid: true,
      probeTimeout: const Duration(milliseconds: 10),
    ).probe();

    expect(result.profile, AndroidSecureStorageProfile.inconsistent);
    expect(result.failureCode, 'native_probe_timeout');
    expect(result.isReady, isFalse);
  });
}
