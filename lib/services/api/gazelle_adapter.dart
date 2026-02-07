import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../../models/app_models.dart';
import '../site_config_service.dart';
import 'site_adapter.dart';
import 'api_exceptions.dart';
import '../../utils/format.dart';

/// Gazelle 站点适配器
/// 用于处理 Gazelle 架构的 PT 站点 JSON API
class GazelleAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  static final Logger _logger = Logger();

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    final swTotal = Stopwatch()..start();
    _siteConfig = config;

    // 加载优惠类型映射配置
    await _loadDiscountMapping();

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.options.baseUrl = _siteConfig.baseUrl;
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

    // 添加 Cookie 拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 动态添加 Cookie
          if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
            options.headers['Cookie'] = _siteConfig.cookie;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          // 检查是否被重定向到登录页面
          final isLoginRedirect =
              response.realUri.toString().contains('login') ||
              response.redirects.any(
                (r) => r.location.toString().contains('login'),
              );
          if (isLoginRedirect) {
            throw SiteAuthenticationException(
              message: 'Cookie已过期，请重新登录更新Cookie',
            );
          }
          handler.next(response);
        },
      ),
    );

    swTotal.stop();
    if (kDebugMode) {
      _logger.d('GazelleAdapter.init: 总耗时=${swTotal.elapsedMilliseconds}ms');
    }
  }

  /// 加载优惠类型映射配置（预留扩展）
  Future<void> _loadDiscountMapping() async {
    // 目前 Gazelle 主要使用 isFreeleech 标记，暂不需要复杂映射
    // 可扩展支持其他优惠类型
  }

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(bool? isFreeleech) {
    if (isFreeleech == true) return DiscountType.free;
    return DiscountType.normal;
  }

  /// 构建下载链接
  /// Gazelle 下载链接格式: {baseUrl}/torrents.php?action=download&id={id}&authkey={authKey}&torrent_pass={passKey}
  String? _buildDownloadUrl(String id) {
    final authKey = _siteConfig.authKey;
    final passKey = _siteConfig.passKey;

    // 如果没有 authKey 或 passKey，返回 null（将通过 genDlToken 方法生成）
    if (authKey == null ||
        authKey.isEmpty ||
        passKey == null ||
        passKey.isEmpty) {
      return null;
    }

    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    return '$baseUrl/torrents.php?action=download&id=$id&authkey=$authKey&torrent_pass=$passKey';
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      // Gazelle API: ajax.php?action=index
      final resp = await _dio.get('/ajax.php?action=index');
      final data = resp.data;

      // 解析响应
      Map<String, dynamic> json;
      if (data is String) {
        json = jsonDecode(data) as Map<String, dynamic>;
      } else {
        json = data as Map<String, dynamic>;
      }

      if (json['status'] != 'success') {
        throw SiteApiException(
          message: '获取用户资料失败: ${json['error'] ?? '未知错误'}',
          responseData: json,
        );
      }

      final response = json['response'] as Map<String, dynamic>? ?? {};
      return _parseMemberProfile(response);
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取用户资料');
    }
  }

  /// 解析 Gazelle 站点的用户资料数据
  MemberProfile _parseMemberProfile(Map<String, dynamic> json) {
    final userstats = json['userstats'] as Map<String, dynamic>? ?? {};

    int parseInt(dynamic v) => FormatUtil.parseInt(v) ?? 0;
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    final uploadedBytes = parseInt(userstats['uploaded']);
    final downloadedBytes = parseInt(userstats['downloaded']);

    return MemberProfile(
      username: (json['username'] ?? '').toString(),
      bonus: parseDouble(userstats['bonusPoints']),
      shareRate: parseDouble(userstats['ratio']),
      uploadedBytes: uploadedBytes,
      downloadedBytes: downloadedBytes,
      uploadedBytesString: Formatters.dataFromBytes(uploadedBytes),
      downloadedBytesString: Formatters.dataFromBytes(downloadedBytes),
      userId: json['id']?.toString(),
      passKey: json['passkey']?.toString(),
      authKey: json['authkey']?.toString(),
      lastAccess: Formatters.parseDateTimeCustom(
        userstats['lastAccess']?.toString(),
      ),
      bonusPerHour: parseDouble(userstats['seedingBonusPointsPerHour']),
      seedingSizeBytes: parseInt(userstats['seedingSize']),
    );
  }

  @override
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      // Gazelle API: ajax.php?action=browse
      final params = <String, dynamic>{'action': 'browse', 'page': pageNumber};

      if (keyword != null && keyword.trim().isNotEmpty) {
        params['searchstr'] = keyword.trim();
      }

      // 收藏搜索
      if (onlyFav == 1) {
        params['action'] = 'bookmarks';
        params['type'] = 'torrents';
      }

      // 合并额外参数
      if (additionalParams != null) {
        params.addAll(additionalParams);
      }

      final resp = await _dio.get('/ajax.php', queryParameters: params);
      final data = resp.data;

      Map<String, dynamic> json;
      if (data is String) {
        json = jsonDecode(data) as Map<String, dynamic>;
      } else {
        json = data as Map<String, dynamic>;
      }

      if (json['status'] != 'success') {
        throw SiteApiException(
          message: '搜索失败: ${json['error'] ?? '未知错误'}',
          responseData: json,
        );
      }

      final response = json['response'] as Map<String, dynamic>? ?? {};
      if (onlyFav == 1) {
        return _parseTorrentBookmarkResult(response, pageNumber, pageSize);
      }
      return _parseTorrentSearchResult(response, pageNumber, pageSize);
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '搜索种子');
    }
  }

  /// 解析 Gazelle 的种子搜索结果
  TorrentSearchResult _parseTorrentSearchResult(
    Map<String, dynamic> json,
    int pageNumber,
    int pageSize,
  ) {
    final results = json['results'] as List? ?? [];
    final List<TorrentItem> items = [];

    for (final group in results) {
      if (group is! Map<String, dynamic>) continue;

      final torrents = group['torrents'] as List? ?? [];
      final groupName = _unescapeHtml(
        (group['groupName'] ?? group['name'] ?? '').toString(),
      );
      final cover = (group['cover'] ?? group['wikiImage'] ?? '').toString();

      for (final torrent in torrents) {
        if (torrent is! Map<String, dynamic>) continue;

        final id = (torrent['torrentId'] ?? torrent['id'] ?? '').toString();
        if (id.isEmpty) continue;

        // 构建用于标签匹配的字符串
        final tagComponents = [
          torrent['remasterTitle'],
          torrent['resolution'],
          torrent['source'],
          torrent['codec'],
          torrent['subtitles'],
        ];
        final tagString = tagComponents
            .where((e) => e != null && e.toString().isNotEmpty)
            .join(' ')
            .replaceAll(',', ' ');

        items.add(
          TorrentItem(
            id: id,
            name: _unescapeHtml(
              (torrent['fileName'] ?? groupName).toString().trim(),
            ),
            smallDescr: '',
            discount: _parseDiscountType(torrent['isFreeleech'] == true),
            discountEndTime: null,
            downloadUrl: _buildDownloadUrl(id),
            seeders: FormatUtil.parseInt(torrent['seeders']) ?? 0,
            leechers: FormatUtil.parseInt(torrent['leechers']) ?? 0,
            sizeBytes: FormatUtil.parseInt(torrent['size']) ?? 0,
            createdDate: Formatters.parseDateTimeCustom(
              torrent['time']?.toString(),
            ),
            imageList: cover.isNotEmpty ? [cover] : const [],
            cover: cover,
            doubanRating: group['doubanRating']?.toString() ?? '0',
            imdbRating: group['imdbRating']?.toString() ?? '0',
            collection: group['bookmarked'] == true,
            tags: TagType.matchTags(tagString),
          ),
        );
      }
    }

    final total = FormatUtil.parseInt(json['pages']) ?? 1;

    return TorrentSearchResult(
      pageNumber: pageNumber,
      pageSize: pageSize,
      total: items.length,
      totalPages: total,
      items: items,
    );
  }

  /// 解析 Gazelle 的书签/收藏结果
  TorrentSearchResult _parseTorrentBookmarkResult(
    Map<String, dynamic> json,
    int pageNumber,
    int pageSize,
  ) {
    final bookmarks = json['bookmarks'] as List? ?? [];
    final List<TorrentItem> items = [];

    for (final group in bookmarks) {
      if (group is! Map<String, dynamic>) continue;

      final torrents = group['torrents'] as List? ?? [];
      final groupName = _unescapeHtml((group['name'] ?? '').toString());
      final cover = (group['image'] ?? '').toString();

      for (final torrent in torrents) {
        if (torrent is! Map<String, dynamic>) continue;

        final id = (torrent['id'] ?? torrent['torrentId'] ?? '').toString();
        if (id.isEmpty) continue;

        // 构建用于标签匹配的字符串
        final tagComponents = [
          torrent['remasterTitle'],
          torrent['resolution'],
          torrent['source'],
          torrent['codec'],
          torrent['subtitles'],
        ];
        final tagString = tagComponents
            .where((e) => e != null && e.toString().isNotEmpty)
            .join(' ')
            .replaceAll(',', ' ');

        items.add(
          TorrentItem(
            id: id,
            name: (torrent['fileName'] ?? groupName).toString().trim(),
            smallDescr: '',
            discount: _parseDiscountType(
              torrent['freeTorrent'] == true || torrent['isFreeleech'] == true,
            ),
            discountEndTime: null,
            downloadUrl: _buildDownloadUrl(id),
            seeders: FormatUtil.parseInt(torrent['seeders']) ?? 0,
            leechers: FormatUtil.parseInt(torrent['leechers']) ?? 0,
            sizeBytes: FormatUtil.parseInt(torrent['size']) ?? 0,
            createdDate: Formatters.parseDateTimeCustom(
              torrent['time']?.toString(),
            ),
            imageList: cover.isNotEmpty ? [cover] : const [],
            cover: cover,
            doubanRating: group['doubanRating']?.toString() ?? '0',
            imdbRating: group['imdbRating']?.toString() ?? '0',
            collection: true,
            tags: TagType.matchTags(tagString),
          ),
        );
      }
    }

    final total = FormatUtil.parseInt(json['pages']) ?? 1;

    return TorrentSearchResult(
      pageNumber: pageNumber,
      pageSize: pageSize,
      total: items.length,
      totalPages: total,
      items: items,
    );
  }

  /// 处理 HTML 转义字符
  String _unescapeHtml(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    // Gazelle 没有专门的详情 API，返回 webviewUrl 供嵌入显示
    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    return TorrentDetail(
      descr: '',
      webviewUrl: '$baseUrl/torrents.php?torrentid=$id',
    );
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    // Gazelle 下载链接格式: /torrents.php?action=download&id={id}
    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    return '$baseUrl/torrents.php?action=download&id=$id';
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    // Gazelle 不支持批量查询下载历史
    return {};
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
    try {
      // Gazelle 书签 API
      final action = make ? 'add' : 'remove';
      await _dio.get(
        '/bookmarks.php',
        queryParameters: {'action': action, 'type': 'torrent', 'id': torrentId},
      );
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '收藏操作');
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      await fetchMemberProfile();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<TorrentCommentList> fetchComments(
    String id, {
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    // Gazelle API 不支持评论接口
    return TorrentCommentList(
      pageNumber: pageNumber,
      pageSize: pageSize,
      total: 0,
      totalPages: 0,
      comments: [],
    );
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 从 JSON 配置文件中加载分类配置
    return await SiteConfigService.getDefaultSearchCategories(
      _siteConfig.baseUrl,
    );
  }
}
