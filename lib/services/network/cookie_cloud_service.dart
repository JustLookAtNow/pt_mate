import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../models/app_models.dart';
import '../site_config_service.dart';
import '../storage/storage_service.dart';

class CookieCloudRemoteData {
  final Map<String, String> cookiesByHost;

  const CookieCloudRemoteData(this.cookiesByHost);
}

enum CookieCloudCandidateType { updateExisting, addPreset, unknown }

class CookieCloudCandidate {
  final CookieCloudCandidateType type;
  final String host;
  final String cookie;
  final SiteConfig? site;
  final SiteConfigTemplate? template;

  const CookieCloudCandidate({
    required this.type,
    required this.host,
    required this.cookie,
    this.site,
    this.template,
  });

  String get title => site?.name ?? template?.name ?? host;
}

class CookieCloudSyncPlan {
  final List<CookieCloudCandidate> updates;
  final List<CookieCloudCandidate> additions;
  final List<CookieCloudCandidate> unknown;

  const CookieCloudSyncPlan({
    required this.updates,
    required this.additions,
    required this.unknown,
  });

  bool get hasChanges => updates.isNotEmpty || additions.isNotEmpty;
  int get totalCandidates => updates.length + additions.length + unknown.length;
}

class CookieCloudApplyResult {
  final int updatedCount;
  final int addedCount;

  const CookieCloudApplyResult({
    required this.updatedCount,
    required this.addedCount,
  });
}

class CookieCloudService {
  CookieCloudService({Dio? dio, StorageService? storage})
    : _dio =
          dio ??
          Dio(BaseOptions(connectTimeout: _timeout, receiveTimeout: _timeout)),
      _storage = storage ?? StorageService.instance;

  static const Duration _timeout = Duration(seconds: 15);
  final Dio _dio;
  final StorageService _storage;

  Future<CookieCloudSyncPlan> fetchSyncPlan([CookieCloudConfig? config]) async {
    final effectiveConfig = config ?? await _storage.loadCookieCloudConfig();
    final remote = await fetchRemoteData(effectiveConfig);
    return buildSyncPlan(remote.cookiesByHost);
  }

  Future<CookieCloudRemoteData> fetchRemoteData(
    CookieCloudConfig config,
  ) async {
    if (!config.isConfigured) {
      throw StateError('Cookie Cloud 配置不完整');
    }

    final baseUrl = config.url.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await _dio.post<dynamic>(
      '$baseUrl/get/${Uri.encodeComponent(config.uuid.trim())}',
      data: {'password': config.password},
      options: Options(responseType: ResponseType.json),
    );

    final body = response.data;
    if (body is! Map) {
      throw const FormatException('Cookie Cloud 响应格式无效');
    }

    final encryptedText = _extractEncryptedText(body);
    if (encryptedText == null || encryptedText.isEmpty) {
      return CookieCloudRemoteData(
        extractCookiesByHost(Map<String, dynamic>.from(body)),
      );
    }

    final plainText = decryptPayload(
      encryptedText,
      uuid: config.uuid,
      password: config.password,
    );
    final decoded = jsonDecode(plainText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Cookie Cloud 明文格式无效');
    }
    return CookieCloudRemoteData(extractCookiesByHost(decoded));
  }

  static String? _extractEncryptedText(Map<dynamic, dynamic> body) {
    for (final key in const [
      'encrypted',
      'encrypted_data',
      'cookie_data',
      'data',
      'payload',
    ]) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final nested = body['data'];
    if (nested is Map) {
      return _extractEncryptedText(nested);
    }
    return null;
  }

  static String decryptPayload(
    String encryptedText, {
    required String uuid,
    required String password,
  }) {
    final keySeed = crypto.md5
        .convert(utf8.encode('$uuid-$password'))
        .toString()
        .substring(0, 16);
    final encryptedBytes = base64Decode(encryptedText);

    if (encryptedBytes.length > 16 &&
        ascii.decode(encryptedBytes.sublist(0, 8), allowInvalid: true) ==
            'Salted__') {
      try {
        final salt = encryptedBytes.sublist(8, 16);
        final cipherText = encryptedBytes.sublist(16);
        final keyIv = deriveOpenSslKeyIv(
          utf8.encode(keySeed),
          salt,
          keyLength: 32,
          ivLength: 16,
        );
        final key = encrypt.Key(Uint8List.fromList(keyIv.sublist(0, 32)));
        final iv = encrypt.IV(Uint8List.fromList(keyIv.sublist(32, 48)));
        final encrypter = encrypt.Encrypter(
          encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
        );
        return encrypter.decrypt(
          encrypt.Encrypted(Uint8List.fromList(cipherText)),
          iv: iv,
        );
      } catch (_) {
        // fall through to fixed-key mode
      }
    }

    final fixedKey = crypto.md5.convert(utf8.encode(keySeed)).bytes;
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(Uint8List.fromList(fixedKey)),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    return encrypter.decrypt(
      encrypt.Encrypted(Uint8List.fromList(encryptedBytes)),
      iv: encrypt.IV(Uint8List(16)),
    );
  }

  static List<int> deriveOpenSslKeyIv(
    List<int> password,
    List<int> salt, {
    required int keyLength,
    required int ivLength,
  }) {
    final targetLength = keyLength + ivLength;
    final bytes = <int>[];
    var previous = <int>[];
    while (bytes.length < targetLength) {
      final digest = crypto.md5.convert([
        ...previous,
        ...password,
        ...salt,
      ]).bytes;
      bytes.addAll(digest);
      previous = digest;
    }
    return bytes.sublist(0, targetLength);
  }

  static Map<String, String> extractCookiesByHost(Map<String, dynamic> json) {
    final candidates = [
      json['cookie_data'],
      json['cookies'],
      json['data'],
      json,
    ];
    final result = <String, String>{};
    for (final candidate in candidates) {
      _collectCookies(candidate, result);
      if (result.isNotEmpty) break;
    }
    return result;
  }

  static void _collectCookies(Object? source, Map<String, String> output) {
    if (source is Map) {
      for (final entry in source.entries) {
        final host = _normalizeCookieDomain(entry.key.toString());
        final cookie = _cookieValueToString(entry.value);
        if (host != null && cookie != null && cookie.isNotEmpty) {
          output[host] = cookie;
        } else {
          _collectCookies(entry.value, output);
        }
      }
    } else if (source is List) {
      for (final item in source) {
        _collectCookies(item, output);
      }
    }
  }

  static String? _cookieValueToString(Object? value) {
    if (value is String) return value.trim();
    if (value is List) {
      final parts = <String>[];
      for (final item in value) {
        if (item is String && item.contains('=')) {
          parts.add(item.split(';').first.trim());
        } else if (item is Map) {
          final name = item['name']?.toString();
          final cookieValue = item['value']?.toString();
          if (name != null && cookieValue != null) {
            parts.add('$name=$cookieValue');
          }
        }
      }
      return parts.join('; ');
    }
    if (value is Map) {
      final cookieString = value['cookieString'] ?? value['cookie'];
      if (cookieString is String) return cookieString.trim();
    }
    return null;
  }

  Future<CookieCloudSyncPlan> buildSyncPlan(
    Map<String, String> cookiesByHost,
  ) async {
    final localSites = await _storage.loadSiteConfigs(includeApiKeys: false);
    final templates = await SiteConfigService.loadPresetSiteTemplates();
    final updates = <CookieCloudCandidate>[];
    final additions = <CookieCloudCandidate>[];
    final unknown = <CookieCloudCandidate>[];
    final matchedTemplateIds = <String>{};

    for (final site in localSites) {
      if (!_shouldSyncCookie(site.siteType)) continue;
      final targetHost = _normalizeUrlHost(site.baseUrl);
      if (targetHost == null) continue;
      final cookie = _buildCookieHeaderForTarget(targetHost, cookiesByHost);
      if (cookie == null) continue;
      if (site.templateId.isNotEmpty) {
        matchedTemplateIds.add(site.templateId);
      }
      if ((site.cookie ?? '') == cookie) continue;
      updates.add(
        CookieCloudCandidate(
          type: CookieCloudCandidateType.updateExisting,
          host: targetHost,
          cookie: cookie,
          site: site,
        ),
      );
    }

    for (final template in templates) {
      if (!_shouldSyncCookie(template.siteType) ||
          matchedTemplateIds.contains(template.id) ||
          _hasLocalSiteForTemplate(template, localSites)) {
        continue;
      }
      final selectedUrl = _bestTemplateUrlForCookies(template, cookiesByHost);
      if (selectedUrl == null) continue;
      final targetHost = _normalizeUrlHost(selectedUrl);
      if (targetHost == null) continue;
      final cookie = _buildCookieHeaderForTarget(targetHost, cookiesByHost);
      if (cookie == null) continue;
      matchedTemplateIds.add(template.id);
      additions.add(
        CookieCloudCandidate(
          type: CookieCloudCandidateType.addPreset,
          host: targetHost,
          cookie: cookie,
          template: template,
        ),
      );
    }

    final unknownDomains = <String>{};
    for (final entry in cookiesByHost.entries) {
      final domain = _normalizeCookieDomain(entry.key);
      if (domain == null || entry.value.trim().isEmpty) continue;
      if (_isKnownCookieDomain(domain, localSites, templates)) continue;
      final canonicalDomain = _cookieDomainForComparison(domain);
      if (unknownDomains.add(canonicalDomain)) {
        unknown.add(
          CookieCloudCandidate(
            type: CookieCloudCandidateType.unknown,
            host: domain,
            cookie: entry.value,
          ),
        );
      }
    }

    return CookieCloudSyncPlan(
      updates: updates,
      additions: additions,
      unknown: unknown,
    );
  }

  Future<String?> checkSiteCookieUpdate(SiteConfig site) async {
    if (!_shouldSyncCookie(site.siteType)) return null;
    final config = await _storage.loadCookieCloudConfig();
    if (!config.isConfigured) return null;
    final remote = await fetchRemoteData(config);
    final siteHost = _normalizeUrlHost(site.baseUrl);
    if (siteHost == null) return null;
    final bestCookie = _buildCookieHeaderForTarget(
      siteHost,
      remote.cookiesByHost,
    );
    if (bestCookie == null || bestCookie == (site.cookie ?? '')) return null;
    return bestCookie;
  }

  Future<CookieCloudApplyResult> applyPlan(
    CookieCloudSyncPlan plan, {
    required Set<CookieCloudCandidate> selectedUpdates,
    required Set<CookieCloudCandidate> selectedAdditions,
  }) async {
    final before = await _storage.loadSiteConfigs(includeApiKeys: false);
    final next = before.toList();
    var updatedCount = 0;
    var addedCount = 0;

    for (final candidate in selectedUpdates) {
      final site = candidate.site;
      if (site == null) continue;
      final index = next.indexWhere((item) => item.id == site.id);
      if (index >= 0) {
        next[index] = next[index].copyWith(cookie: candidate.cookie);
        updatedCount++;
      }
    }

    for (final candidate in selectedAdditions) {
      final template = candidate.template;
      if (template == null) continue;
      final selectedUrl = _bestTemplateUrl(candidate.host, template);
      final id =
          '${template.id}-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      final site = template
          .toSiteConfig(selectedUrl: selectedUrl, cookie: candidate.cookie)
          .copyWith(id: id);
      next.add(site);
      addedCount++;
    }

    try {
      await _storage.saveSiteConfigs(
        next.map((c) => c.copyWith(apiKey: null)).toList(),
      );
    } catch (_) {
      await _storage.saveSiteConfigs(
        before.map((c) => c.copyWith(apiKey: null)).toList(),
      );
      rethrow;
    }

    await _storage.saveCookieCloudLastSync(
      syncedAt: DateTime.now(),
      summary: '更新 $updatedCount 个站点，新增 $addedCount 个站点',
    );
    return CookieCloudApplyResult(
      updatedCount: updatedCount,
      addedCount: addedCount,
    );
  }

  static String? _bestTemplateUrl(String host, SiteConfigTemplate template) {
    for (final url in template.baseUrls) {
      final urlHost = _normalizeUrlHost(url);
      if (urlHost != null && _hostsRelated(host, urlHost)) return url;
    }
    return template.primaryUrl ??
        (template.baseUrls.isNotEmpty ? template.baseUrls.first : null);
  }

  static bool _shouldSyncCookie(SiteType siteType) =>
      siteType == SiteType.nexusphpweb || siteType == SiteType.gazelle;

  static bool _hasLocalSiteForTemplate(
    SiteConfigTemplate template,
    List<SiteConfig> localSites,
  ) {
    for (final site in localSites) {
      if (site.templateId.isNotEmpty && site.templateId == template.id) {
        return true;
      }
      final siteHost = _normalizeUrlHost(site.baseUrl);
      if (siteHost == null) continue;
      for (final url in template.baseUrls) {
        final templateHost = _normalizeUrlHost(url);
        if (templateHost != null && _hostsRelated(siteHost, templateHost)) {
          return true;
        }
      }
    }
    return false;
  }

  static String? _bestTemplateUrlForCookies(
    SiteConfigTemplate template,
    Map<String, String> cookiesByHost,
  ) {
    final urls = <String>[
      if (template.primaryUrl != null) template.primaryUrl!,
      ...template.baseUrls.where((url) => url != template.primaryUrl),
    ];
    for (final url in urls) {
      final host = _normalizeUrlHost(url);
      if (host != null &&
          _buildCookieHeaderForTarget(host, cookiesByHost) != null) {
        return url;
      }
    }
    return null;
  }

  static bool _isKnownCookieDomain(
    String cookieDomain,
    List<SiteConfig> localSites,
    List<SiteConfigTemplate> templates,
  ) {
    for (final site in localSites) {
      final host = _normalizeUrlHost(site.baseUrl);
      if (host != null && _cookieDomainCoversHost(cookieDomain, host)) {
        return true;
      }
    }
    for (final template in templates) {
      for (final url in template.baseUrls) {
        final host = _normalizeUrlHost(url);
        if (host != null && _cookieDomainCoversHost(cookieDomain, host)) {
          return true;
        }
      }
    }
    return false;
  }

  static String? _buildCookieHeaderForTarget(
    String targetHost,
    Map<String, String> cookiesByHost,
  ) {
    final sources = <_CookieDomainSource>[];
    for (final entry in cookiesByHost.entries) {
      final domain = _normalizeCookieDomain(entry.key);
      if (domain == null || entry.value.trim().isEmpty) continue;
      if (!_cookieDomainCoversHost(domain, targetHost)) continue;
      sources.add(
        _CookieDomainSource(
          domain: domain,
          cookie: entry.value,
          priority: _cookieDomainPriority(domain, targetHost),
        ),
      );
    }
    if (sources.isEmpty) return null;
    sources.sort((a, b) => a.priority.compareTo(b.priority));

    final valuesByName = <String, String>{};
    for (final source in sources) {
      valuesByName.addAll(_parseCookieHeader(source.cookie));
    }
    if (valuesByName.isEmpty) return sources.last.cookie.trim();
    return valuesByName.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static Map<String, String> _parseCookieHeader(String cookie) {
    final result = <String, String>{};
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final equalsIndex = trimmed.indexOf('=');
      if (equalsIndex <= 0) continue;
      final name = trimmed.substring(0, equalsIndex).trim();
      final value = trimmed.substring(equalsIndex + 1).trim();
      if (name.isEmpty) continue;
      result[name] = value;
    }
    return result;
  }

  static int _cookieDomainPriority(String cookieDomain, String targetHost) {
    final comparable = _cookieDomainForComparison(cookieDomain);
    final labelCount = comparable
        .split('.')
        .where((part) => part.isNotEmpty)
        .length;
    final exactBonus = comparable == targetHost ? 1000 : 0;
    return exactBonus + labelCount;
  }

  static String? _normalizeUrlHost(String value) {
    var raw = value.trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    return _normalizePlainHost(host);
  }

  static String? _normalizeCookieDomain(String value) {
    var raw = value.trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (raw.contains('://')) {
      final host = Uri.tryParse(raw)?.host;
      if (host == null || host.isEmpty) return null;
      raw = host;
    } else {
      raw = raw.split('/').first;
    }
    final hasLeadingDot = raw.startsWith('.');
    final host = _normalizePlainHost(raw);
    if (host == null) return null;
    return hasLeadingDot && !host.startsWith('.') ? '.$host' : host;
  }

  static String? _normalizePlainHost(String value) {
    var host = value.trim().toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    while (host.startsWith('..')) {
      host = host.substring(1);
    }
    return host.isEmpty ? null : host;
  }

  static String _cookieDomainForComparison(String cookieDomain) {
    var domain = cookieDomain.trim().toLowerCase();
    while (domain.startsWith('.')) {
      domain = domain.substring(1);
    }
    if (domain.endsWith('.')) domain = domain.substring(0, domain.length - 1);
    return domain;
  }

  static bool _cookieDomainCoversHost(String cookieDomain, String host) {
    final comparableDomain = _cookieDomainForComparison(cookieDomain);
    if (comparableDomain.isEmpty) return false;
    return host == comparableDomain || host.endsWith('.$comparableDomain');
  }

  static bool _hostsRelated(String a, String b) {
    if (a == b) return true;
    return a.endsWith('.$b') || b.endsWith('.$a');
  }
}

class _CookieDomainSource {
  final String domain;
  final String cookie;
  final int priority;

  const _CookieDomainSource({
    required this.domain,
    required this.cookie,
    required this.priority,
  });
}
