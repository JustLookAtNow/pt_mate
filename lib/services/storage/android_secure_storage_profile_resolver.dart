import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidSecureStorageProfile {
  oaepGcm,
  pkcs1Gcm,
  pkcs1Cbc,
  fresh,
  inconsistent,
  unsupported,
}

class AndroidSecureStorageProbeResult {
  const AndroidSecureStorageProbeResult({
    required this.profile,
    required this.hasEncryptedEntries,
    required this.hasWrappedKeys,
    this.keyCipher,
    this.storageCipher,
    this.failureCode,
  });

  final AndroidSecureStorageProfile profile;
  final String? keyCipher;
  final String? storageCipher;
  final bool hasEncryptedEntries;
  final bool hasWrappedKeys;
  final String? failureCode;

  bool get isReady => switch (profile) {
    AndroidSecureStorageProfile.oaepGcm ||
    AndroidSecureStorageProfile.pkcs1Gcm ||
    AndroidSecureStorageProfile.pkcs1Cbc ||
    AndroidSecureStorageProfile.fresh => true,
    AndroidSecureStorageProfile.inconsistent ||
    AndroidSecureStorageProfile.unsupported => false,
  };
}

class AndroidSecureStorageFlushResult {
  const AndroidSecureStorageFlushResult({
    required this.isSuccessful,
    this.failureCode,
  });

  final bool isSuccessful;
  final String? failureCode;
}

class AndroidSecureStorageProfileResolver {
  AndroidSecureStorageProfileResolver({
    MethodChannel channel = const MethodChannel(_channelName),
    bool? isAndroid,
    Duration probeTimeout = const Duration(milliseconds: 800),
  }) : _channel = channel,
       _probeTimeout = probeTimeout,
       _isAndroid =
           isAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  static const _channelName = 'pt_mate/secure_storage_profile';
  static const _probeMethodName = 'probeAndroidSecureStorage';
  static const _initializeFreshMethodName =
      'initializeFreshAndroidSecureStorage';
  static const _flushMethodName = 'flushAndroidSecureStorage';
  static const _oaepCipher = 'RSA_ECB_OAEPwithSHA_256andMGF1Padding';
  static const _pkcs1Cipher = 'RSA_ECB_PKCS1Padding';
  static const _gcmCipher = 'AES_GCM_NoPadding';
  static const _cbcCipher = 'AES_CBC_PKCS7Padding';

  final MethodChannel _channel;
  final bool _isAndroid;
  final Duration _probeTimeout;

  Future<AndroidSecureStorageProbeResult> probe() async {
    return _invokeNative(
      methodName: _probeMethodName,
      timeoutFailureCode: 'native_probe_timeout',
      genericFailureCode: 'probe_failed',
    );
  }

  Future<AndroidSecureStorageProbeResult> initializeFreshOaepGcm() async {
    return _invokeNative(
      methodName: _initializeFreshMethodName,
      timeoutFailureCode: 'native_fresh_initialization_timeout',
      genericFailureCode: 'fresh_initialization_failed',
    );
  }

  Future<AndroidSecureStorageFlushResult> flush() async {
    if (!_isAndroid) {
      return const AndroidSecureStorageFlushResult(isSuccessful: true);
    }

    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>(_flushMethodName)
          .timeout(_probeTimeout);
      if (response == null ||
          response['status'] is! String ||
          (response['failureCode'] != null &&
              response['failureCode'] is! String)) {
        return const AndroidSecureStorageFlushResult(
          isSuccessful: false,
          failureCode: 'invalid_flush_result',
        );
      }
      final status = response['status'] as String;
      final failureCode = response['failureCode'] as String?;
      if (status == 'ready' && failureCode == null) {
        return const AndroidSecureStorageFlushResult(isSuccessful: true);
      }
      if (status == 'unavailable' &&
          failureCode != null &&
          failureCode.isNotEmpty) {
        return AndroidSecureStorageFlushResult(
          isSuccessful: false,
          failureCode: failureCode,
        );
      }
      return const AndroidSecureStorageFlushResult(
        isSuccessful: false,
        failureCode: 'invalid_flush_result',
      );
    } on TimeoutException {
      return const AndroidSecureStorageFlushResult(
        isSuccessful: false,
        failureCode: 'native_flush_timeout',
      );
    } on PlatformException catch (error) {
      return AndroidSecureStorageFlushResult(
        isSuccessful: false,
        failureCode: 'native_${error.code}',
      );
    } catch (_) {
      return const AndroidSecureStorageFlushResult(
        isSuccessful: false,
        failureCode: 'secure_storage_flush_failed',
      );
    }
  }

  Future<AndroidSecureStorageProbeResult> _invokeNative({
    required String methodName,
    required String timeoutFailureCode,
    required String genericFailureCode,
  }) async {
    if (!_isAndroid) {
      return const AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.unsupported,
        hasEncryptedEntries: false,
        hasWrappedKeys: false,
        failureCode: 'not_android',
      );
    }

    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>(methodName)
          .timeout(_probeTimeout);
      return _parse(response);
    } on TimeoutException {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: false,
        hasWrappedKeys: false,
        failureCode: timeoutFailureCode,
      );
    } on PlatformException catch (error) {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: false,
        hasWrappedKeys: false,
        failureCode: 'native_${error.code}',
      );
    } catch (_) {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: false,
        hasWrappedKeys: false,
        failureCode: genericFailureCode,
      );
    }
  }

  AndroidSecureStorageProbeResult _parse(Map<String, Object?>? response) {
    if (response == null ||
        response['hasEncryptedEntries'] is! bool ||
        response['hasWrappedKeys'] is! bool) {
      return const AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: false,
        hasWrappedKeys: false,
        failureCode: 'invalid_probe_result',
      );
    }

    final profileName = response['profile'];
    final status = response['status'];
    final profile = profileName is String
        ? AndroidSecureStorageProfile.values.asNameMap()[profileName]
        : null;
    if (profile == null || !_statusMatchesProfile(status, profile)) {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: response['hasEncryptedEntries']! as bool,
        hasWrappedKeys: response['hasWrappedKeys']! as bool,
        failureCode: 'invalid_probe_result',
      );
    }

    final keyCipher = response['keyCipher'];
    final storageCipher = response['storageCipher'];
    final failureCode = response['failureCode'];
    if ((keyCipher != null && keyCipher is! String) ||
        (storageCipher != null && storageCipher is! String) ||
        (failureCode != null && failureCode is! String)) {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: response['hasEncryptedEntries']! as bool,
        hasWrappedKeys: response['hasWrappedKeys']! as bool,
        failureCode: 'invalid_probe_result',
      );
    }

    final hasEncryptedEntries = response['hasEncryptedEntries']! as bool;
    final hasWrappedKeys = response['hasWrappedKeys']! as bool;
    if (!_detailsMatchProfile(
      profile: profile,
      keyCipher: keyCipher as String?,
      storageCipher: storageCipher as String?,
      hasEncryptedEntries: hasEncryptedEntries,
      hasWrappedKeys: hasWrappedKeys,
      failureCode: failureCode as String?,
    )) {
      return AndroidSecureStorageProbeResult(
        profile: AndroidSecureStorageProfile.inconsistent,
        hasEncryptedEntries: hasEncryptedEntries,
        hasWrappedKeys: hasWrappedKeys,
        failureCode: 'invalid_probe_result',
      );
    }

    return AndroidSecureStorageProbeResult(
      profile: profile,
      keyCipher: keyCipher,
      storageCipher: storageCipher,
      hasEncryptedEntries: hasEncryptedEntries,
      hasWrappedKeys: hasWrappedKeys,
      failureCode: failureCode,
    );
  }

  bool _detailsMatchProfile({
    required AndroidSecureStorageProfile profile,
    required String? keyCipher,
    required String? storageCipher,
    required bool hasEncryptedEntries,
    required bool hasWrappedKeys,
    required String? failureCode,
  }) {
    final readyDetailsAreSafe =
        failureCode == null && (!hasEncryptedEntries || hasWrappedKeys);
    return switch (profile) {
      AndroidSecureStorageProfile.oaepGcm =>
        readyDetailsAreSafe &&
            keyCipher == _oaepCipher &&
            storageCipher == _gcmCipher,
      AndroidSecureStorageProfile.pkcs1Gcm =>
        readyDetailsAreSafe &&
            keyCipher == _pkcs1Cipher &&
            storageCipher == _gcmCipher,
      AndroidSecureStorageProfile.pkcs1Cbc =>
        readyDetailsAreSafe &&
            keyCipher == _pkcs1Cipher &&
            storageCipher == _cbcCipher,
      AndroidSecureStorageProfile.fresh =>
        keyCipher == null &&
            storageCipher == null &&
            !hasEncryptedEntries &&
            !hasWrappedKeys &&
            failureCode == null,
      AndroidSecureStorageProfile.inconsistent ||
      AndroidSecureStorageProfile.unsupported =>
        failureCode != null && failureCode.isNotEmpty,
    };
  }

  bool _statusMatchesProfile(
    Object? status,
    AndroidSecureStorageProfile profile,
  ) {
    return switch (profile) {
      AndroidSecureStorageProfile.oaepGcm ||
      AndroidSecureStorageProfile.pkcs1Gcm ||
      AndroidSecureStorageProfile.pkcs1Cbc => status == 'ready',
      AndroidSecureStorageProfile.fresh => status == 'fresh',
      AndroidSecureStorageProfile.inconsistent => status == 'inconsistent',
      AndroidSecureStorageProfile.unsupported => status == 'unsupported',
    };
  }
}
