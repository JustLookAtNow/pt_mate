import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'services/storage/storage_service.dart';
import 'services/logging/log_file_service.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final enabled = await StorageService.instance.loadLogToFileEnabled();
      await LogFileService.instance.init(enabled: enabled);

      runApp(const MTeamApp());
    },
    (error, stack) {
      if (!kIsWeb) {
        LogFileService.instance.append('Uncaught error: $error\n$stack');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        LogFileService.instance.append(line);
      },
    ),
  );
}
