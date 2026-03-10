import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// Fetch site icons (.png and .ico) from PT-depiler repo and place into assets/sites_icon
/// Matching rule: remote file stem (e.g. `mteam` from `mteam.png`) must match a site key
/// listed in `assets/sites_manifest.json` (the filename without `.json`).
///
/// Usage:
///   dart run tool/fetch_site_icons.dart
///
/// Optional: set `GITHUB_TOKEN` env var to increase rate limits.
Future<void> main() async {
  final manifestPath = 'assets/sites_manifest.json';
  final outputDirPath = 'assets/sites_icon';
  const githubApiUrl =
      'https://api.github.com/repos/pt-plugins/PT-depiler/contents/public/icons/site';
  const rawBaseUrl =
      'https://raw.githubusercontent.com/pt-plugins/PT-depiler/master/public/icons/site/';

  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Manifest not found: $manifestPath');
    exitCode = 1;
    return;
  }

  final manifestJson = jsonDecode(await manifestFile.readAsString());
  if (manifestJson is! Map<String, dynamic>) {
    stderr.writeln('Invalid manifest JSON structure. Expected an object.');
    exitCode = 1;
    return;
  }

  final sitesList = manifestJson['sites'];
  if (sitesList is! List) {
    stderr.writeln('Invalid manifest: missing "sites" array.');
    exitCode = 1;
    return;
  }

  final Set<String> siteKeys = sitesList
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.endsWith('.json'))
      .map((s) => s.substring(0, s.length - '.json'.length).toLowerCase())
      .toSet();

  final outDir = Directory(outputDirPath);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final token = Platform.environment['GITHUB_TOKEN'];
  final dio = Dio(
    BaseOptions(
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'pt-mate-fetch-site-icons-script',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ),
  );

  List<dynamic> listing;
  try {
    final res = await dio.get(githubApiUrl);
    if (res.statusCode != 200 || res.data is! List) {
      stderr.writeln(
        'Failed to list GitHub directory: status ${res.statusCode}',
      );
      exitCode = 2;
      return;
    }
    listing = res.data as List<dynamic>;
  } catch (e) {
    stderr.writeln('Error listing GitHub directory: $e');
    exitCode = 2;
    return;
  }

  final List<Map<String, dynamic>> iconFiles = listing
      .whereType<Map<String, dynamic>>()
      .where((item) => item['type'] == 'file')
      .where((item) {
        final name = (item['name'] as String?)?.toLowerCase() ?? '';
        return name.endsWith('.png') || name.endsWith('.ico');
      })
      .toList();

  // 优先处理 PNG；对于只有 ICO 的站点，转换为 PNG
  final Set<String> pngStems = iconFiles
      .map((item) => (item['name'] as String?)?.toLowerCase() ?? '')
      .where((name) => name.endsWith('.png'))
      .map((name) => name.substring(0, name.lastIndexOf('.')))
      .toSet();

  int matched = 0;
  int downloaded = 0;
  int converted = 0;
  final List<String> skipped = [];
  final Set<String> matchedStems = {};
  final Set<String> createdStems = {};

  for (final item in iconFiles) {
    final name = item['name'] as String?;
    if (name == null || name.isEmpty) continue;

    final lower = name.toLowerCase();
    final stem = lower.contains('.')
        ? lower.substring(0, lower.lastIndexOf('.'))
        : lower;
    if (!siteKeys.contains(stem)) {
      skipped.add(name);
      continue;
    }
    // 如果远端存在同名 PNG，则优先使用 PNG，跳过 ICO
    final bool isIco = lower.endsWith('.ico');
    if (isIco && pngStems.contains(stem)) {
      continue;
    }
    matched++;
    matchedStems.add(stem);

    final rawUrl = '$rawBaseUrl$name';
    try {
      final pngOutFile = File('${outDir.path}/$stem.png');
      if (pngOutFile.existsSync()) {
        // 跳过已有 PNG 文件
        stdout.writeln('Skip existing: ${pngOutFile.path}');
        continue;
      }
      final res = await dio.get<List<int>>(
        rawUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode == 200 && res.data != null) {
        final bytes = res.data!;
        if (lower.endsWith('.png')) {
          await pngOutFile.writeAsBytes(bytes);
          downloaded++;
          stdout.writeln('Downloaded $name -> ${pngOutFile.path}');
          createdStems.add(stem);
        } else if (isIco) {
          final img.Image? image =
              img.decodeIco(Uint8List.fromList(bytes)) ??
              img.decodeImage(Uint8List.fromList(bytes));
          if (image == null) {
            stderr.writeln('Failed to decode ICO: $name');
            continue;
          }

          // Find the best frame (largest dimensions)
          img.Image bestFrame = image;
          if (image.frames.length > 1) {
            for (final frame in image.frames) {
              if (frame.width > bestFrame.width ||
                  (frame.width == bestFrame.width &&
                      frame.height > bestFrame.height)) {
                bestFrame = frame;
              }
            }
            if (bestFrame != image) {
              stdout.writeln(
                'Selected best frame ${bestFrame.width}x${bestFrame.height} for $name',
              );
            }
          }

          final pngBytes = img.encodePng(bestFrame);
          await pngOutFile.writeAsBytes(pngBytes);
          converted++;
          stdout.writeln('Converted ICO $name -> ${pngOutFile.path}');
          createdStems.add(stem);
        } else {
          // 非预期格式，跳过
          stderr.writeln('Unexpected format: $name');
        }
      } else {
        stderr.writeln('Failed to download $name: status ${res.statusCode}');
      }
    } catch (e) {
      stderr.writeln('Error downloading $name: $e');
    }
  }

  stdout.writeln('Matched icons: $matched');
  stdout.writeln('Downloaded icons: $downloaded');
  stdout.writeln('Converted ICO -> PNG: $converted');
  if (skipped.isNotEmpty) {
    stdout.writeln('Skipped (no matching site key): ${skipped.length}');
  }
  stdout.writeln('Output dir: ${outDir.path}');

  final Set<String> missingStems = siteKeys.difference(matchedStems);
  final siteDio = Dio();
  for (final stem in missingStems) {
    final pngOutFile = File('${outDir.path}/$stem.png');
    if (pngOutFile.existsSync()) {
      continue;
    }

    final siteJsonPath = 'assets/sites/$stem.json';
    final siteFile = File(siteJsonPath);
    if (!siteFile.existsSync()) {
      continue;
    }

    try {
      final content = await siteFile.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      final primaryUrl = (data['primaryUrl'] as String?)?.trim();
      if (primaryUrl == null || primaryUrl.isEmpty) {
        continue;
      }

      Uri u;
      try {
        u = Uri.parse(primaryUrl);
      } catch (_) {
        continue;
      }
      final faviconUri = Uri(
        scheme: u.scheme,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: '/favicon.ico',
      );

      try {
        final res = await siteDio.get<List<int>>(
          faviconUri.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (code) => code != null && code >= 200 && code < 400,
          ),
        );
        if (res.data == null) {
          continue;
        }
        final bytes = res.data!;
        img.Image? image = img.decodeIco(Uint8List.fromList(bytes));
        if (image != null) {
          // Find the best frame (largest dimensions)
          img.Image bestFrame = image;
          if (image.frames.length > 1) {
            for (final frame in image.frames) {
              if (frame.width > bestFrame.width ||
                  (frame.width == bestFrame.width &&
                      frame.height > bestFrame.height)) {
                bestFrame = frame;
              }
            }
          }

          final pngBytes = img.encodePng(bestFrame);
          await pngOutFile.writeAsBytes(pngBytes);
          converted++;
          createdStems.add(stem);
          stdout.writeln(
            'Converted favicon ICO for $stem -> ${pngOutFile.path}',
          );
          continue;
        }
        image = img.decodeImage(Uint8List.fromList(bytes));
        if (image != null) {
          final pngBytes = img.encodePng(image);
          await pngOutFile.writeAsBytes(pngBytes);
          downloaded++;
          createdStems.add(stem);
          stdout.writeln('Downloaded favicon for $stem -> ${pngOutFile.path}');
        }
      } catch (_) {
        continue;
      }
    } catch (_) {
      continue;
    }
  }

  // 更新对应站点 JSON，logo 字段统一指向 PNG 资源
  for (final stem in createdStems) {
    final pngFile = File('${outDir.path}/$stem.png');
    if (!pngFile.existsSync()) {
      // 没有任何已下载或已存在的图标，跳过
      continue;
    }

    final siteJsonPath = 'assets/sites/$stem.json';
    final siteFile = File(siteJsonPath);
    if (!siteFile.existsSync()) {
      // 找不到对应的站点配置文件，跳过
      stdout.writeln('Skip JSON update (missing): $siteJsonPath');
      continue;
    }

    try {
      final content = await siteFile.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      // 写入或更新 logo 字段为资源路径
      data['logo'] = 'assets/sites_icon/$stem.png';
      // 写回文件（格式化输出，便于阅读）
      await siteFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      stdout.writeln(
        'Updated logo in $siteJsonPath -> assets/sites_icon/$stem.png',
      );
    } catch (e) {
      stderr.writeln('Error updating logo for $siteJsonPath: $e');
    }
  }
}
