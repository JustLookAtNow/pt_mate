import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogFileService {
  LogFileService._();
  static final LogFileService instance = LogFileService._();

  bool _enabled = false;
  IOSink? _sink;
  DateTime? _currentDate;
  String? _currentPath;
  final _lock = <void>[]; // Simple lock mechanism

  bool get enabled => _enabled;

  Future<void> init({bool? enabled}) async {
    if (kIsWeb) {
      _enabled = false;
      return;
    }
    if (enabled == null) {
      _enabled = false;
    } else {
      _enabled = enabled;
    }
    if (_enabled) {
      await _ensureSinkForToday();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (kIsWeb) {
      _enabled = false;
      await _closeSink();
      return;
    }
    _enabled = value;
    if (_enabled) {
      await _ensureSinkForToday();
    } else {
      await _closeSink();
    }
  }

  void append(String line) {
    if (!_enabled || kIsWeb) return;
    final now = DateTime.now();

    // Check if rotation is needed
    if (_currentDate == null || !_isSameDay(_currentDate!, now)) {
      _rotateTo(now);
    }

    // If locked (initializing/rotating), we might lose this log or need to buffer.
    // For simplicity and safety, we just try to write if sink is available.
    // Ideally we should buffer, but let's first prevent the crash.
    final sink = _sink;
    if (sink != null) {
      try {
        sink.writeln('[${_ts(now)}] $line');
      } catch (_) {
        // Ignore write errors to prevent app crash
      }
    }
  }

  Future<String?> currentLogFilePath() async {
    if (kIsWeb) return null;
    if (_currentPath != null) return _currentPath;
    await _ensureSinkForToday();
    return _currentPath;
  }

  Future<String> logsDirectoryPath() async {
    final dir = await _resolveBaseDir();
    final logs = Directory('${dir.path}${Platform.pathSeparator}logs');
    if (!await logs.exists()) {
      await logs.create(recursive: true);
    }
    return logs.path;
  }

  Future<void> _rotateTo(DateTime date) async {
    _currentDate = date;
    unawaited(_ensureSinkForToday());
  }

  Future<void> _ensureSinkForToday() async {
    // Simple lock check
    if (_lock.isNotEmpty) return;
    _lock.add(null); // Acquire lock

    try {
      final base = await _resolveBaseDir();
      final logsDir = Directory('${base.path}${Platform.pathSeparator}logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      final name = _fileNameFor(DateTime.now());
      final file = File('${logsDir.path}${Platform.pathSeparator}$name');
      _currentPath = file.path;
      await _closeSink();
      _sink = file.openWrite(mode: FileMode.append);
    } catch (_) {
      // Ignore initialization errors
    } finally {
      if (_lock.isNotEmpty) _lock.removeLast(); // Release lock
    }
  }

  Future<void> _closeSink() async {
    try {
      await _sink?.flush();
    } catch (_) {}
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  Future<int> clearLogs() async {
    if (kIsWeb) return 0;
    await _closeSink();
    final dirPath = await logsDirectoryPath();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final entity in dir.list()) {
      try {
        if (entity is File) {
          await entity.delete();
          count++;
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
          count++;
        }
      } catch (_) {}
    }
    _currentPath = null;
    _currentDate = null;
    if (_enabled) {
      await _ensureSinkForToday();
    }
    return count;
  }

  Future<Directory> _resolveBaseDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return await getApplicationSupportDirectory();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _fileNameFor(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return 'app-$y$m$d.log';
  }

  String _ts(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }
}
