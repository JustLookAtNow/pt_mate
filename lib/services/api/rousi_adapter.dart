import 'package:dio/dio.dart';

import 'package:logger/logger.dart';
import '../../models/app_models.dart';
import 'site_adapter.dart';
import '../../utils/format.dart';

/// RousiPro 站点适配器
/// 实现 Rousi API v1 的调用
class RousiAdapter implements SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  static final Logger _logger = Logger();

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    _dio.interceptors.clear();
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 设置baseUrl
          if (options.baseUrl.isEmpty || options.baseUrl == '/') {
            var base = _siteConfig.baseUrl.trim();
            if (base.endsWith('/')) base = base.substring(0, base.length - 1);
            options.baseUrl = base;
          }

          // 设置认证头
          options.headers['Accept'] = 'application/json';
          // Rousi API 使用 Bearer Token，存在 apiKey 中
          if (_siteConfig.apiKey != null && _siteConfig.apiKey!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer ${_siteConfig.apiKey}';
          }

          return handler.next(options);
        },
      ),
    );
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final response = await _dio.get(
        '/api/v1/profile',
        queryParameters: {'include_fields[user]': 'seeding_leeching_data'},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          return _parseMemberProfile(data['data']);
        } else {
          throw Exception('API返回错误: ${data['message']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('获取用户资料失败: $e');
    }
  }

  MemberProfile _parseMemberProfile(Map<String, dynamic> data) {
    final uploadedBytes = (data['uploaded'] ?? 0).toInt();
    final downloadedBytes = (data['downloaded'] ?? 0).toInt();

    // seeding_leeching_data
    final slData = data['seeding_leeching_data'] as Map<String, dynamic>?;
    final seedingSize = slData?['seeding_size']?.toInt();

    // bonus -> karma
    final bonus = (data['karma'] ?? 0).toDouble();
    // bonusPerHour -> seeding_karma_per_hour? or seeding_points_per_hour?
    // 文档中有 karma (魔力值) 和 credits (PT币)
    // 通常 bonus 指的是魔力值
    final bonusPerHour = (data['seeding_karma_per_hour'] ?? 0).toDouble();

    return MemberProfile(
      username: data['username'] ?? '',
      bonus: bonus,
      shareRate: (data['ratio'] ?? 0).toDouble(),
      uploadedBytes: uploadedBytes,
      downloadedBytes: downloadedBytes,
      uploadedBytesString: Formatters.dataFromBytes(uploadedBytes),
      downloadedBytesString: Formatters.dataFromBytes(downloadedBytes),
      userId: data['id']?.toString(),
      passKey: null, // API V1 不直接返回 passkey (虽然 account settings 有)
      lastAccess: data['last_active_at']?.toString(),
      bonusPerHour: bonusPerHour,
      seedingSizeBytes: seedingSize,
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
    final Map<String, dynamic> params = {
      'page': pageNumber,
      'page_size': pageSize,
    };

    if (keyword != null && keyword.isNotEmpty) {
      params['keyword'] = keyword;
    }

    // 处理分类参数
    if (additionalParams != null) {
      if (additionalParams.containsKey('category')) {
        params['category'] = additionalParams['category'];
      }
      // 其他参数直接追加?
    }

    // API 文档未提及 onlyFav 参数，暂时忽略或查看是否支持书签过滤
    // 文档只显示: page, page_size, category, keyword

    try {
      final response = await _dio.get(
        '/api/v1/torrents',
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          return _parseTorrentSearchResult(data['data']);
        } else {
          throw Exception('搜索失败: ${data['message']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('搜索出错: $e');
    }
  }

  TorrentSearchResult _parseTorrentSearchResult(Map<String, dynamic> data) {
    final torrents = data['torrents'] as List? ?? [];
    final items = torrents.map((e) => _parseTorrentItem(e)).toList();

    return TorrentSearchResult(
      pageNumber: data['page'] ?? 1,
      pageSize: data['page_size'] ?? 20,
      total: (data['total'] ?? 0).toInt(),
      totalPages: (data['total_pages'] ?? 1).toInt(),
      items: items,
    );
  }

  TorrentItem _parseTorrentItem(dynamic item) {
    final map = item as Map<String, dynamic>;

    // 解析促销
    DiscountType discount = DiscountType.normal;
    String? discountEndTime;
    final promotion = map['promotion'] as Map<String, dynamic>?;
    if (promotion != null) {
      final type = promotion['type'] as int?;
      // 1=普通, 2=免费, 3=2X, 4=2X免费, 5=50%, 6=2X50%, 7=30%
      switch (type) {
        case 2:
          discount = DiscountType.free;
          break;
        case 3:
          // 2X Upload. Download normal.
          discount = DiscountType.normal;
          break;
        case 4:
          discount = DiscountType.twoXFree;
          break;
        case 5:
          discount = DiscountType.percent50;
          break;
        case 6:
          discount = DiscountType.twoX50Percent;
          break;
        case 7:
          discount = DiscountType.percent30;
          break;
        default:
          discount = DiscountType.normal;
      }

      if (promotion['until'] != null) {
        discountEndTime = promotion['until'].toString();
      }
    }

    // 图片
    final cover = map['cover_image'] as String? ?? '';

    // 标签: API 列表没直接返回tags字段，从标题匹配
    final name = map['title'] as String? ?? '';
    final tags = TagType.matchTags(name);

    return TorrentItem(
      id: (map['id'] ?? map['uuid']).toString(), // 优先使用ID，或者UUID
      name: name,
      smallDescr: map['subtitle'] as String? ?? '',
      discount: discount,
      discountEndTime: discountEndTime,
      downloadUrl: null, // 列表不返回下载链接，需详情获取
      seeders: (map['seeders'] ?? 0).toInt(),
      leechers: (map['leechers'] ?? 0).toInt(),
      sizeBytes: (map['size'] ?? 0).toInt(),
      createdDate: map['created_at'] ?? '',
      imageList: [],
      cover: cover,
      downloadStatus: DownloadStatus.none, // API 暂不支持返回当前用户下载状态
      collection: false, // API 列表数据未显示是否收藏
      tags: tags,
      comments: 0, // 列表数据未显示评论数，详情接口有
    );
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    try {
      final response = await _dio.get('/api/v1/torrents/$id');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          final info = data['data'];
          // 描述内容
          return TorrentDetail(descr: info['description'] ?? '');
        } else {
          throw Exception('获取详情失败: ${data['message']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('fetchTorrentDetail error: $e');
    }
  }

  @override
  Future<TorrentCommentList> fetchComments(
    String id, {
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/torrents/$id/comments',
        queryParameters: {'page': pageNumber, 'page_size': pageSize},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          final d = data['data'];
          final list = d['comments'] as List? ?? [];
          final comments = list.map((c) => _parseComment(c, id)).toList();

          return TorrentCommentList(
            pageNumber: d['page'] ?? 1,
            pageSize: d['page_size'] ?? 20,
            total: (d['total'] ?? 0).toInt(),
            totalPages: (d['total_pages'] ?? 1).toInt(),
            comments: comments,
          );
        }
      }
      return TorrentCommentList(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: 0,
        totalPages: 0,
        comments: [],
      );
    } catch (e) {
      return TorrentCommentList(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: 0,
        totalPages: 0,
        comments: [],
      );
    }
  }

  TorrentComment _parseComment(Map<String, dynamic> c, String tId) {
    return TorrentComment(
      id: c['id'].toString(),
      createdDate: c['created_at'] ?? '',
      lastModifiedDate: '',
      torrentId: tId,
      author: c['username'] ?? '',
      text: c['content'] ?? '',
      editedBy: '',
      subject: '',
    );
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    if (url != null && url.isNotEmpty) return url;

    // 如果没有URL，尝试获取详情
    try {
      final response = await _dio.get('/api/v1/torrents/$id');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          final dUrl = data['data']['download_url'];
          if (dUrl != null && dUrl is String && dUrl.isNotEmpty) {
            return dUrl;
          }
        }
      }
    } catch (e) {
      _logger.e('genDlToken error: $e');
    }
    throw Exception('无法获取下载链接');
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    return {'data': <String, dynamic>{}};
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
    // API 文档未提供收藏/取消收藏接口
    // 暂时留空
    return;
  }

  @override
  Future<bool> testConnection() async {
    try {
      // 尝试请求 profile
      await fetchMemberProfile();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    try {
      final response = await _dio.get('/api/v1/categories');
      final list = <SearchCategoryConfig>[];

      // 默认加个全站
      list.add(
        SearchCategoryConfig(id: 'all', displayName: '全部', parameters: '{}'),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0 && data['data'] != null) {
          final cats = data['data'] as List;
          for (var c in cats) {
            final name = c['name'] as String;
            final label = c['label'] as String;
            // final id = c['id'];

            list.add(
              SearchCategoryConfig(
                id: 'cat_$name',
                displayName: label,
                parameters: '{"category": "$name"}',
              ),
            );
          }
        }
      }
      return list;
    } catch (e) {
      return [];
    }
  }
}
