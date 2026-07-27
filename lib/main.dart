import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'services/storage/storage_service.dart';
import 'services/logging/log_file_service.dart';
import 'services/network/proxy_service.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      String? secureStorageFailureCode;
      try {
        await StorageService.instance.initializeSecureStorage();
      } on SecureStorageUnavailableException catch (error) {
        secureStorageFailureCode = error.code;
      } catch (error) {
        secureStorageFailureCode = error.runtimeType.toString();
      }

      final enabled = await StorageService.instance.loadLogToFileEnabled();
      await LogFileService.instance.init(enabled: enabled);
      await StorageService.instance.loadVisibleTags();

      if (secureStorageFailureCode != null) {
        LogFileService.instance.append(
          'Secure storage '
          'profile=${StorageService.instance.secureStorageProfile?.name ?? 'unknown'}, '
          'state=${StorageService.instance.secureStorageState.name}, '
          'code=$secureStorageFailureCode',
        );
      }

      // 代理密码依赖安全存储，预检失败时不得初始化代理。
      if (StorageService.instance.canAccessSensitiveStorage) {
        try {
          await ProxyService.instance.init();
        } on SecureStorageUnavailableException catch (error) {
          ProxyService.instance
            ..isProxyEnabled = false
            ..proxyUsername = ''
            ..proxyPassword = '';
          LogFileService.instance.append(
            'Secure storage '
            'profile=${StorageService.instance.secureStorageProfile?.name ?? 'unknown'}, '
            'state=${StorageService.instance.secureStorageState.name}, '
            'code=${error.code}',
          );
        }
      }

      runApp(const MTeamApp());
    },
    (error, stack) {
      if (!kIsWeb && kDebugMode) {
        LogFileService.instance.append('Uncaught error: $error\n$stack');
      } else if (!kIsWeb) {
        LogFileService.instance.append('Application error category=uncaught');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (kDebugMode) {
          parent.print(zone, line);
          LogFileService.instance.append(line);
        }
      },
    ),
  );
}
