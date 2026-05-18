import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> secureSharedPreferencesFile() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final file = File('${supportDir.path}/shared_preferences.json');
      if (await file.exists()) {
        await Process.run('chmod', ['600', file.path]);
        if (kDebugMode) {
          final logger = LoggerInstanceForStub();
          logger.d('SharedPreferences 文件权限已设为 600: ${file.path}');
        }
      }
    } catch (_) {
      // 捕获异常，确保不阻塞主流程
    }
  }
}

// 避免引入额外的 Logger 依赖，这里用简单的命令行输出
class LoggerInstanceForStub {
  void d(String message) {
    debugPrint('StoragePermissionHelper: $message');
  }
}
