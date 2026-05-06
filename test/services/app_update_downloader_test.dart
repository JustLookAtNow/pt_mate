import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/app_update_downloader.dart';

void main() {
  group('AppUpdateDownloader mirror ranking', () {
    test('prioritizes higher sampled throughput over lower latency', () {
      final downloader = AppUpdateDownloader.instance;
      final candidates = <String>[
        'https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
        'https://gh-proxy.com/https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
        'https://mirror.ghproxy.com/https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
      ];

      final ranked = downloader.rankCandidatesForTesting(candidates, {
        candidates[0]: const MirrorProbeResult(
          isAvailable: true,
          latencyMs: 150,
          bytesReceived: 900000,
          elapsedMs: 3000,
          contentLength: 12000000,
        ),
        candidates[1]: const MirrorProbeResult(
          isAvailable: true,
          latencyMs: 80,
          bytesReceived: 450000,
          elapsedMs: 3000,
          contentLength: 12000000,
        ),
        candidates[2]: const MirrorProbeResult(
          isAvailable: false,
          latencyMs: null,
          bytesReceived: 0,
          elapsedMs: 0,
          contentLength: null,
        ),
      });

      expect(ranked.map((item) => item.url), [
        candidates[0],
        candidates[1],
        candidates[2],
      ]);
      expect(ranked.first.label, 'GitHub 官方源');
    });

    test('keeps unavailable mirrors in original fallback order', () {
      final downloader = AppUpdateDownloader.instance;
      final candidates = <String>[
        'https://gh-proxy.com/https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
        'https://mirror.ghproxy.com/https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
        'https://ghproxy.net/https://github.com/JustLookAtNow/pt_mate/releases/download/v1/app.apk',
      ];

      final ranked = downloader.rankCandidatesForTesting(candidates, {
        for (final url in candidates)
          url: const MirrorProbeResult(
            isAvailable: false,
            latencyMs: null,
            bytesReceived: 0,
            elapsedMs: 0,
            contentLength: null,
          ),
      });

      expect(ranked.map((item) => item.url), candidates);
    });
  });
}
