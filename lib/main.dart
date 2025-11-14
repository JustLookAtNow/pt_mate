import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'services/storage/storage_service.dart';
import 'services/logging/log_file_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final enabled = await StorageService.instance.loadLogToFileEnabled();

  runZonedGuarded(() {
    // 拦截所有print输出，同时保留控制台输出
    runZoned(() {
      runApp(const MTeamApp());
    }, zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        LogFileService.instance.append(line);
      },
    ));
  }, (error, stack) {
    if (!kIsWeb) {
      LogFileService.instance.append('Uncaught error: $error\n$stack');
    }
  });

  await LogFileService.instance.init(enabled: enabled);
}
