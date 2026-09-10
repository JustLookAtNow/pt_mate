import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_models.dart';
import '../../models/purchase_models.dart';
import 'site_adapter.dart';
import 'purchasable_adapter.dart';
import 'api_exceptions.dart';
import '../../utils/format.dart';
import '../network/timeout_retry.dart';

/// RousiPro（PeerGo）站点适配器
/// 实现 PeerGo API v1 的调用
class RousiAdapter implements SiteAdapter, PurchasableAdapter {
  /// [dio] 仅用于测试注入；为空时使用内部构造的默认实例
  RousiAdapter({Dio? dio}) : _injectedDio = dio;

  final Dio? _injectedDio;

  /// 幂等键生成器：写请求在网络重试时必须复用同一个 key
  static const Uuid _uuid = Uuid();

  late SiteConfig _siteConfig;
  late Dio _dio;

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;

    _dio =
        _injectedDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
            },
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

    // 注入 Dio 时由调用方自行决定日志策略（避免测试输出被请求日志淹没）
    if (kDebugMode && _injectedDio == null) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: true,
          responseBody: true,
          error: true,
        ),
      );
    }
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final response = await _dio.get(
        '/api/v1/profile',
        queryParameters: {'include_fields[user]': 'seeding_leeching_data'},
      );

      final data = response.data;
      if (data['code'] == 0 && data['data'] != null) {
        return _parseMemberProfile(data['data']);
      } else {
        throw SiteApiException(
          message: '获取用户资料失败: ${data['message'] ?? '未知错误'}',
          responseData: data,
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取用户资料');
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
      lastAccess: Formatters.parseDateTimeCustom(
        data['last_active_at']?.toString(),
        fieldName: 'lastAccess',
      ),
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

      final data = response.data;
      if (data['code'] == 0 && data['data'] != null) {
        return _parseTorrentSearchResult(data['data']);
      } else {
        throw SiteApiException(
          message: '搜索失败: ${data['message'] ?? '未知错误'}',
          responseData: data,
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '搜索种子');
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

  /// 解析种子标识：PeerGo 以数字 ID 为准，`uuid` 仅作为旧响应回退
  String _resolveTorrentId(Map<String, dynamic> map) {
    final numericId = map['id']?.toString().trim() ?? '';
    if (numericId.isNotEmpty) return numericId;
    return map['uuid']?.toString().trim() ?? '';
  }

  /// 宽容解析布尔值（服务端可能返回 bool / num / string）
  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  /// 提取响应体的业务错误信息
  String? _messageOf(dynamic data) {
    if (data is Map) {
      final message = data['message']?.toString().trim() ?? '';
      if (message.isNotEmpty && message.toLowerCase() != 'success') {
        return message;
      }
    }
    return null;
  }

  TorrentItem _parseTorrentItem(dynamic item) {
    final map = item as Map<String, dynamic>;

    // 解析促销：PeerGo 返回 is_active，已过期/未激活的促销不参与优惠判定
    DiscountType discount = DiscountType.normal;
    String? discountEndTime;
    final promotion = map['promotion'] as Map<String, dynamic>?;
    if (promotion != null) {
      final type = (promotion['type'] as num?)?.toInt();
      final isActive = _asBool(promotion['is_active'], fallback: true);
      if (isActive) {
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
      // PeerGo 的种子公开身份是数字 ID，`uuid` 字段仅作为旧响应回退
      id: _resolveTorrentId(map),
      name: name,
      smallDescr: map['subtitle'] as String? ?? '',
      discount: discount,
      discountEndTime: Formatters.parseDateTimeCustom(
        discountEndTime,
        fieldName: 'discountEndTime',
      ),
      downloadUrl: null, // 列表不返回下载链接，需详情获取
      seeders: (map['seeders'] ?? 0).toInt(),
      leechers: (map['leechers'] ?? 0).toInt(),
      sizeBytes: (map['size'] ?? 0).toInt(),
      createdDate: Formatters.parseDateTimeCustom(
        map['created_at']?.toString(),
        fieldName: 'createdDate',
      ),
      imageList: [],
      cover: cover,
      downloadStatus: DownloadStatus.none, // API 暂不支持返回当前用户下载状态
      collection: false, // API 列表数据未显示是否收藏
      tags: tags,
      comments: 0, // 列表数据未显示评论数，详情接口有
    );
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(
    String id, {
    String? description,
    String? detailUrl,
  }) async {
    try {
      if (description != null && description.isNotEmpty) {
        return TorrentDetail(descr: description, descrHtml: description);
      }

      final response = await _dio.get('/api/v1/torrents/$id');
      final data = response.data;
      if (data['code'] == 0 && data['data'] != null) {
        final info = data['data'];

        // 解析图片列表并加到描述最前面 (BBCode 格式)
        String imageBBCode = '';
        final images = info['images'] as List?;
        if (images != null && images.isNotEmpty) {
          for (var img in images) {
            final url = img['url'];
            if (url != null) {
              imageBBCode += '[img]$url[/img]\n';
            }
          }
          if (imageBBCode.isNotEmpty) {
            imageBBCode += '\n';
          }
        }

        final descr = info['description'] ?? '';
        return TorrentDetail(
          descr: imageBBCode + descr,
          price: (info['price'] as num?)?.toInt() ?? 0,
          isPurchased: _asBool(info['is_purchased']),
        );
      } else {
        throw SiteApiException(
          message: '获取详情失败: ${data['message'] ?? '未知错误'}',
          responseData: data,
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取种子详情');
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
      createdDate: Formatters.parseDateTimeCustom(
        c['created_at']?.toString(),
        fieldName: 'createdDate',
      ),
      lastModifiedDate: Formatters.parseDateTimeCustom(
        c['created_at']?.toString(),
        fieldName: 'lastModifiedDate',
      ),
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

    try {
      final response = await _dio.get('/api/v1/torrents/$id');
      final data = response.data;
      if (data['code'] == 0 && data['data'] != null) {
        final info = data['data'] as Map<String, dynamic>;
        final dUrl = info['download_url'];
        if (dUrl is String && dUrl.isNotEmpty) {
          return dUrl;
        }

        // 付费种子未购买时 PeerGo 会返回空的 download_url，需引导用户先购买
        final isPurchased = _asBool(info['is_purchased'], fallback: true);
        final price = (info['price'] as num?)?.toInt() ?? 0;
        if (price > 0 && !isPurchased) {
          throw SitePurchaseRequiredException(
            torrentId: id,
            torrentTitle: info['title']?.toString(),
          );
        }
      }
      throw SiteApiException(message: '无法获取下载链接', responseData: data);
    } catch (e) {
      if (e is SitePurchaseRequiredException) {
        rethrow;
      }
      throw ApiExceptionAdapter.wrapError(e, '生成下载链接');
    }
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    return {'data': <String, dynamic>{}};
  }

  // ==== 购买 API（PeerGo，需要 torrent:purchase:read / write scope） ====

  @override
  Future<PurchaseStatus> fetchPurchaseStatus(String torrentId) async {
    try {
      final response = await _dio.get('/api/v1/torrents/$torrentId/purchase');
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] != null) {
        return PurchaseStatus.fromJson(
          (data['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw SiteApiException(
        message: '获取购买状态失败: ${_messageOf(data) ?? '未知错误'}',
        responseData: data,
      );
    } on DioException catch (e) {
      throw _mapPurchaseError(e, fallbackMessage: '获取购买状态失败');
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取购买状态');
    }
  }

  @override
  Future<PurchaseResult> purchaseTorrent(
    String torrentId, {
    int? expectedPrice,
  }) async {
    // 幂等键在同一逻辑请求的所有网络重试中复用，避免重复扣款
    final idempotencyKey = _uuid.v4();
    final body = <String, dynamic>{'expected_price': ?expectedPrice};

    try {
      final response = await retryOnTimeout(
        () => _dio.post(
          '/api/v1/torrents/$torrentId/purchase',
          data: body,
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        ),
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] != null) {
        return PurchaseResult.fromJson(
          (data['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw SitePurchaseException(
        reason: PurchaseFailureReason.unknown,
        message: '购买失败: ${_messageOf(data) ?? '未知错误'}',
        detail: data?.toString(),
      );
    } on DioException catch (e) {
      throw _mapPurchaseError(e, fallbackMessage: '购买失败');
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '购买种子');
    }
  }

  @override
  Future<PurchaseHistoryPage> fetchPurchaseHistory({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/purchases',
        queryParameters: {'page': pageNumber, 'page_size': pageSize},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] != null) {
        return PurchaseHistoryPage.fromJson(
          (data['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw SiteApiException(
        message: '获取购买记录失败: ${_messageOf(data) ?? '未知错误'}',
        responseData: data,
      );
    } on DioException catch (e) {
      throw _mapPurchaseError(e, fallbackMessage: '获取购买记录失败');
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取购买记录');
    }
  }

  /// 将购买相关的 HTTP 错误映射为可操作的中文提示
  ///
  /// 购买路由的 403 表示缺少 scope、账号受限或购买关闭，
  /// 不能沿用通用的「登录已失效」提示。
  SiteException _mapPurchaseError(
    DioException e, {
    required String fallbackMessage,
  }) {
    final statusCode = e.response?.statusCode;
    final serverMessage = _messageOf(e.response?.data);

    switch (statusCode) {
      case 400:
        return SitePurchaseException(
          reason: PurchaseFailureReason.notAllowed,
          message: serverMessage ?? '购买请求参数无效',
          statusCode: statusCode,
        );
      case 401:
        return SiteAuthenticationException(
          statusCode: statusCode,
          detail: serverMessage,
        );
      case 402:
        return SitePurchaseException(
          reason: PurchaseFailureReason.insufficientBalance,
          message: serverMessage ?? '魔力值余额不足，无法购买该种子',
          statusCode: statusCode,
        );
      case 403:
        return SitePurchaseException(
          reason: PurchaseFailureReason.forbidden,
          message:
              serverMessage ?? 'API Key 缺少 torrent:purchase:write 权限，或该种子已关闭购买',
          statusCode: statusCode,
        );
      case 404:
        return SiteServiceException(
          message: serverMessage ?? '种子不存在或已下架',
          statusCode: statusCode,
        );
      case 409:
        return SitePurchaseException(
          reason: PurchaseFailureReason.priceChanged,
          message: serverMessage ?? '种子价格已变化，请重新确认后再购买',
          statusCode: statusCode,
        );
      default:
        return ApiExceptionAdapter.wrapError(e, fallbackMessage);
    }
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
