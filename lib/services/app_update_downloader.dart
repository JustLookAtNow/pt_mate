import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';

import 'update_service.dart';

class AppUpdateProgress {
  final String message;
  final bool isError;
  final bool isFinal;

  const AppUpdateProgress({
    required this.message,
    this.isError = false,
    this.isFinal = false,
  });
}

class AppUpdateDownloader {
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
      final url = ranked[i];
      onProgress(
        AppUpdateProgress(message: '正在尝试下载源 ${i + 1}/${ranked.length}'),
      );
      try {
        await _executeOta(
          url: url,
          version: updateResult.latestVersion,
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

    // Convert GitHub release tag url to release asset direct url.
    // Example:
    // https://github.com/{owner}/{repo}/releases/tag/v1.2.3
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

  Future<List<String>> _rankCandidates(List<String> candidates) async {
    final probes = await Future.wait(
      candidates.map((url) async {
        final latency = await _probeLatency(url);
        return (url: url, latency: latency);
      }),
    );

    final available = probes.where((item) => item.latency != null).toList()
      ..sort((a, b) => a.latency!.compareTo(b.latency!));

    final unavailable = probes.where((item) => item.latency == null);
    return <String>[
      ...available.map((item) => item.url),
      ...unavailable.map((item) => item.url),
    ];
  }

  Future<int?> _probeLatency(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _probeDio.head(url);
      if ((response.statusCode ?? 500) < 400) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      stopwatch.stop();
    }
  }

  Future<void> _executeOta({
    required String url,
    required String? version,
    required ValueChanged<AppUpdateProgress> onProgress,
  }) async {
    final completer = Completer<void>();

    final filenameVersion = (version ?? 'latest').replaceAll(
      RegExp(r'[^0-9A-Za-z._-]'),
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
              final msg = progressValue == null
                  ? '正在下载更新包...'
                  : '正在下载更新包 ${progressValue.toStringAsFixed(0)}%';
              onProgress(AppUpdateProgress(message: msg));
              return;
            }

            if (status == 'INSTALLING') {
              onProgress(
                const AppUpdateProgress(
                  message: '下载完成，正在打开安装界面...',
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
}
