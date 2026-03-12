import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';

import 'update_service.dart';

class AppUpdateProgress {
  final String message;
  final double? progress;
  final int? downloadedBytes;
  final int? totalBytes;
  final bool isError;
  final bool isFinal;

  const AppUpdateProgress({
    required this.message,
    this.progress,
    this.downloadedBytes,
    this.totalBytes,
    this.isError = false,
    this.isFinal = false,
  });
}

class AppUpdateDownloader {
  // ⚡ Bolt: Cache RegExp to avoid recompiling on every call
  static final RegExp _invalidCharsRegExp = RegExp(r'[^0-9A-Za-z._-]');

  AppUpdateDownloader._();

  static final AppUpdateDownloader instance = AppUpdateDownloader._();

  static const List<String> _githubProxyPrefixes = <String>[
    '',
    'https://gh-proxy.com/',
    'https://mirror.ghproxy.com/',
    'https://ghproxy.net/',
    'https://github.abskoop.workers.dev/',
  ];

  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
      followRedirects: true,
      validateStatus: (code) => code != null && code >= 200 && code < 400,
    ),
  );

  bool get supportsInAppUpdate =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> startAndroidUpdate({
    required UpdateCheckResult updateResult,
    required ValueChanged<AppUpdateProgress> onProgress,
  }) async {
    if (!supportsInAppUpdate) {
      throw StateError('当前平台不支持应用内安装更新');
    }

    final directApkUrl = _resolveAndroidApkUrl(updateResult);
    if (directApkUrl == null) {
      throw StateError('未找到可用的 Android APK 下载地址');
    }

    final candidates = _buildCandidateUrls(directApkUrl);
    final ranked = await _rankCandidates(candidates);
    if (ranked.isEmpty) {
      throw StateError('未找到可用的下载源');
    }

    Object? lastError;
    for (var i = 0; i < ranked.length; i++) {
      final candidate = ranked[i];
      onProgress(
        AppUpdateProgress(message: '正在尝试下载源 ${i + 1}/${ranked.length}'),
      );
      try {
        await _executeOta(
          url: candidate.url,
          version: updateResult.latestVersion,
          totalBytes: candidate.contentLength,
          onProgress: onProgress,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw StateError('更新下载失败：${lastError ?? '未知错误'}');
  }

  String? resolveFallbackUrl(UpdateCheckResult updateResult) {
    if (updateResult.downloadUrl != null &&
        updateResult.downloadUrl!.isNotEmpty) {
      return updateResult.downloadUrl!;
    }
    return 'https://github.com/JustLookAtNow/pt_mate/releases';
  }

  String? _resolveAndroidApkUrl(UpdateCheckResult updateResult) {
    if (updateResult.androidDownloadUrl != null &&
        updateResult.androidDownloadUrl!.isNotEmpty) {
      return updateResult.androidDownloadUrl;
    }

    final fromDownloadUrl = updateResult.downloadUrl;
    if (fromDownloadUrl == null || fromDownloadUrl.isEmpty) {
      return null;
    }

    if (fromDownloadUrl.toLowerCase().endsWith('.apk')) {
      return fromDownloadUrl;
    }

    final uri = Uri.tryParse(fromDownloadUrl);
    if (uri == null || uri.host != 'github.com') {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.length >= 5 &&
        segments[2] == 'releases' &&
        segments[3] == 'tag') {
      final owner = segments[0];
      final repo = segments[1];
      final tag = segments[4];
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final filename = 'pt_mate-$version-arm64-v8a.apk';
      return 'https://github.com/$owner/$repo/releases/download/$tag/$filename';
    }

    return null;
  }

  List<String> _buildCandidateUrls(String directUrl) {
    final candidates = <String>{};
    for (final prefix in _githubProxyPrefixes) {
      candidates.add(prefix.isEmpty ? directUrl : '$prefix$directUrl');
    }
    return candidates.toList();
  }

  Future<List<({String url, int? contentLength})>> _rankCandidates(
    List<String> candidates,
  ) async {
    final probes = await Future.wait(
      candidates.map((url) async {
        final probe = await _probeUrl(url);
        return (
          url: url,
          latency: probe.latency,
          contentLength: probe.contentLength,
        );
      }),
    );

    final available = probes.where((item) => item.latency != null).toList()
      ..sort((a, b) => a.latency!.compareTo(b.latency!));

    final unavailable = probes.where((item) => item.latency == null);
    return <({String url, int? contentLength})>[
      ...available.map(
        (item) => (url: item.url, contentLength: item.contentLength),
      ),
      ...unavailable.map(
        (item) => (url: item.url, contentLength: item.contentLength),
      ),
    ];
  }

  Future<({int? latency, int? contentLength})> _probeUrl(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _probeDio.head(url);
      if ((response.statusCode ?? 500) < 400) {
        return (
          latency: stopwatch.elapsedMilliseconds,
          contentLength: _extractContentLength(response),
        );
      }
      return (latency: null, contentLength: _extractContentLength(response));
    } catch (_) {
      return (latency: null, contentLength: null);
    } finally {
      stopwatch.stop();
    }
  }

  int? _extractContentLength(Response<dynamic> response) {
    final header = response.headers.value(Headers.contentLengthHeader);
    if (header == null || header.isEmpty) {
      return null;
    }
    return int.tryParse(header);
  }

  Future<void> _executeOta({
    required String url,
    required String? version,
    required int? totalBytes,
    required ValueChanged<AppUpdateProgress> onProgress,
  }) async {
    final completer = Completer<void>();

    final filenameVersion = (version ?? 'latest').replaceAll(
      _invalidCharsRegExp,
      '_',
    );
    final destinationFilename = 'pt_mate-$filenameVersion-arm64-v8a.apk';

    late final StreamSubscription<OtaEvent> sub;
    sub = OtaUpdate()
        .execute(url, destinationFilename: destinationFilename)
        .listen(
          (event) {
            final status = event.status.toString().split('.').last;
            final value = event.value ?? '';

            if (status == 'DOWNLOADING') {
              final progressValue = double.tryParse(value);
              final normalizedProgress = progressValue == null
                  ? null
                  : (progressValue.clamp(0, 100) / 100).toDouble();
              final downloadedBytes =
                  normalizedProgress == null || totalBytes == null
                  ? null
                  : (normalizedProgress * totalBytes).round();
              onProgress(
                AppUpdateProgress(
                  message: _buildDownloadMessage(
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    progressValue: progressValue,
                  ),
                  progress: normalizedProgress,
                  downloadedBytes: downloadedBytes,
                  totalBytes: totalBytes,
                ),
              );
              return;
            }

            if (status == 'INSTALLING') {
              onProgress(
                AppUpdateProgress(
                  message: totalBytes == null
                      ? '下载完成，正在打开安装界面...'
                      : '下载完成 ${_formatBytes(totalBytes)}，正在打开安装界面...',
                  progress: 1,
                  downloadedBytes: totalBytes,
                  totalBytes: totalBytes,
                  isFinal: true,
                ),
              );
              if (!completer.isCompleted) {
                completer.complete();
              }
              return;
            }

            if (status.contains('ERROR')) {
              final err = value.isEmpty ? status : value;
              if (!completer.isCompleted) {
                completer.completeError(StateError(err));
              }
            }
          },
          onError: (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          cancelOnError: true,
        );

    try {
      await completer.future;
    } finally {
      await sub.cancel();
    }
  }

  String _buildDownloadMessage({
    required int? downloadedBytes,
    required int? totalBytes,
    required double? progressValue,
  }) {
    if (downloadedBytes != null && totalBytes != null) {
      return '已下载 ${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
    }
    if (progressValue != null) {
      return '正在下载更新包 ${progressValue.toStringAsFixed(0)}%';
    }
    return '正在下载更新包...';
  }

  String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final fractionDigits = unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }
}
