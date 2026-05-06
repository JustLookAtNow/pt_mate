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

@immutable
class MirrorProbeResult {
  final bool isAvailable;
  final int? latencyMs;
  final int bytesReceived;
  final int elapsedMs;
  final int? contentLength;

  const MirrorProbeResult({
    required this.isAvailable,
    required this.latencyMs,
    required this.bytesReceived,
    required this.elapsedMs,
    required this.contentLength,
  });

  int? get estimatedBytesPerSecond {
    if (!isAvailable || bytesReceived <= 0 || elapsedMs <= 0) {
      return null;
    }
    return ((bytesReceived * 1000) / elapsedMs).round();
  }
}

@immutable
class RankedMirrorSource {
  final String url;
  final String label;
  final int? contentLength;
  final MirrorProbeResult probeResult;

  const RankedMirrorSource({
    required this.url,
    required this.label,
    required this.contentLength,
    required this.probeResult,
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
  static const Duration _probeConnectTimeout = Duration(seconds: 2);
  static const Duration _probeReceiveTimeout = Duration(seconds: 4);
  static const Duration _speedTestDuration = Duration(seconds: 3);
  static const int _speedTestByteLimit = 1024 * 1024;

  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: _probeConnectTimeout,
      receiveTimeout: _probeReceiveTimeout,
      followRedirects: true,
      validateStatus: (code) => code != null && code >= 200 && code < 400,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Mobile Safari/537.36',
        'Accept-Encoding': 'identity',
      },
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
    onProgress(const AppUpdateProgress(message: '正在测速下载源...'));
    final ranked = await _rankCandidates(candidates);
    if (ranked.isEmpty) {
      throw StateError('未找到可用的下载源');
    }

    final bestSource = ranked.first;
    onProgress(
      AppUpdateProgress(
        message: _buildMirrorSelectedMessage(bestSource, ranked.length),
      ),
    );

    Object? lastError;
    for (var i = 0; i < ranked.length; i++) {
      final candidate = ranked[i];
      onProgress(
        AppUpdateProgress(
          message: i == 0
              ? '正在使用 ${candidate.label} 下载更新包...'
              : '正在切换到 ${candidate.label}（${i + 1}/${ranked.length}）...',
        ),
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

  Future<List<RankedMirrorSource>> _rankCandidates(
    List<String> candidates,
  ) async {
    final probeResults = <String, MirrorProbeResult>{};
    await Future.wait(
      candidates.map((url) async {
        probeResults[url] = await _probeUrl(url);
      }),
    );
    return rankCandidatesForTesting(candidates, probeResults);
  }

  @visibleForTesting
  List<RankedMirrorSource> rankCandidatesForTesting(
    List<String> candidates,
    Map<String, MirrorProbeResult> probeResults,
  ) {
    final ranked = <({int index, RankedMirrorSource source})>[];
    for (var i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      final probeResult =
          probeResults[url] ??
          const MirrorProbeResult(
            isAvailable: false,
            latencyMs: null,
            bytesReceived: 0,
            elapsedMs: 0,
            contentLength: null,
          );
      ranked.add((
        index: i,
        source: RankedMirrorSource(
          url: url,
          label: _describeSource(url),
          contentLength: probeResult.contentLength,
          probeResult: probeResult,
        ),
      ));
    }

    ranked.sort((a, b) {
      final availabilityCompare = _compareBool(
        a.source.probeResult.isAvailable,
        b.source.probeResult.isAvailable,
      );
      if (availabilityCompare != 0) {
        return availabilityCompare;
      }

      if (!a.source.probeResult.isAvailable &&
          !b.source.probeResult.isAvailable) {
        return a.index.compareTo(b.index);
      }

      final speedA = a.source.probeResult.estimatedBytesPerSecond ?? 0;
      final speedB = b.source.probeResult.estimatedBytesPerSecond ?? 0;
      final speedCompare = speedB.compareTo(speedA);
      if (speedCompare != 0) {
        return speedCompare;
      }

      final latencyA = a.source.probeResult.latencyMs ?? 1 << 30;
      final latencyB = b.source.probeResult.latencyMs ?? 1 << 30;
      final latencyCompare = latencyA.compareTo(latencyB);
      if (latencyCompare != 0) {
        return latencyCompare;
      }

      return a.index.compareTo(b.index);
    });

    return ranked.map((item) => item.source).toList();
  }

  Future<MirrorProbeResult> _probeUrl(String url) async {
    final stopwatch = Stopwatch()..start();
    final cancelToken = CancelToken();
    Timer? timer;
    ResponseBody? responseBody;
    var bytesReceived = 0;
    int? latencyMs;
    int? contentLength;

    try {
      timer = Timer(_speedTestDuration, () {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel('speed-test-timeout');
        }
      });

      final response = await _probeDio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: const {'Range': 'bytes=0-1048575'},
        ),
      );
      latencyMs = stopwatch.elapsedMilliseconds;
      contentLength = _extractContentLength(response);
      responseBody = response.data;
      if ((response.statusCode ?? 500) >= 400 || responseBody == null) {
        return MirrorProbeResult(
          isAvailable: false,
          latencyMs: latencyMs,
          bytesReceived: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
          contentLength: contentLength,
        );
      }

      await for (final chunk in responseBody.stream) {
        bytesReceived += chunk.length;
        if (bytesReceived >= _speedTestByteLimit && !cancelToken.isCancelled) {
          cancelToken.cancel('speed-test-sample-complete');
        }
      }
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        return MirrorProbeResult(
          isAvailable: false,
          latencyMs: latencyMs,
          bytesReceived: bytesReceived,
          elapsedMs: stopwatch.elapsedMilliseconds,
          contentLength: contentLength,
        );
      }
    } catch (_) {
      return MirrorProbeResult(
        isAvailable: false,
        latencyMs: latencyMs,
        bytesReceived: bytesReceived,
        elapsedMs: stopwatch.elapsedMilliseconds,
        contentLength: contentLength,
      );
    } finally {
      timer?.cancel();
      stopwatch.stop();
    }

    return MirrorProbeResult(
      isAvailable: true,
      latencyMs: latencyMs,
      bytesReceived: bytesReceived,
      elapsedMs: stopwatch.elapsedMilliseconds,
      contentLength: contentLength,
    );
  }

  int? _extractContentLength(Response<dynamic> response) {
    final contentRange = response.headers.value('content-range');
    if (contentRange != null && contentRange.isNotEmpty) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
      if ((response.statusCode ?? 0) == 206) {
        return null;
      }
    }

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

  String _buildMirrorSelectedMessage(
    RankedMirrorSource source,
    int totalCandidates,
  ) {
    final speed = source.probeResult.estimatedBytesPerSecond;
    final speedLabel = speed == null ? null : _formatBytes(speed);
    if (speedLabel == null) {
      return '已选择 ${source.label}，准备开始下载（共测速 $totalCandidates 个源）';
    }
    return '已选择 ${source.label}，测速约 $speedLabel/s，准备开始下载';
  }

  String _describeSource(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return '下载源';
    }

    if (uri.host == 'github.com' ||
        uri.host == 'objects.githubusercontent.com') {
      return 'GitHub 官方源';
    }

    if (uri.host.isEmpty) {
      return '下载源';
    }

    return uri.host;
  }

  int _compareBool(bool a, bool b) {
    if (a == b) {
      return 0;
    }
    return a ? -1 : 1;
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
