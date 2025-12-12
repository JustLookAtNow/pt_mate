import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../../models/app_models.dart';
import '../site_config_service.dart';
import 'site_adapter.dart';
import '../../utils/format.dart';

/// M-Team站点适配器实现
class MTeamAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  Map<String, String>? _discountMapping;
  Map<String, String>? _tagMapping;
  static final Logger _logger = Logger();

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    final swTotal = Stopwatch()..start();
    _siteConfig = config;

    // 加载优惠类型映射配置
    final swDiscount = Stopwatch()..start();
    await _loadDiscountMapping();
    swDiscount.stop();
    // 加载标签映射配置
    await _loadTagMapping();
    if (kDebugMode) {
      _logger.d(
        'MTeamAdapter.init: 加载优惠映射耗时=${swDiscount.elapsedMilliseconds}ms',
      );
    }

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    final swInterceptors = Stopwatch()..start();
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

          // 动态设置API密钥和UA
          options.headers['accept'] = 'application/json, text/plain, */*';
          options.headers['user-agent'] = 'MTeamApp/1.0 (Flutter; Dio)';
          final hasExplicitKey =
              options.headers.containsKey('x-api-key') &&
              ((options.headers['x-api-key']?.toString().isNotEmpty) == true);
          final siteKey = _siteConfig.apiKey ?? '';
          if (!hasExplicitKey && siteKey.isNotEmpty) {
            options.headers['x-api-key'] = siteKey;
          }

          return handler.next(options);
        },
      ),
    );
    swInterceptors.stop();
    if (kDebugMode) {
      _logger.d(
        'MTeamAdapter.init: 配置Dio与拦截器耗时=${swInterceptors.elapsedMilliseconds}ms',
      );
    }
    swTotal.stop();
    if (kDebugMode) {
      _logger.d('MTeamAdapter.init: 总耗时=${swTotal.elapsedMilliseconds}ms');
    }
  }

  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
      final template = await SiteConfigService.getTemplateById(
        '',
        SiteType.mteam,
      );
      if (template?.discountMapping != null) {
        _discountMapping = Map<String, String>.from(template!.discountMapping);
      }
      final specialMapping = await SiteConfigService.getDiscountMapping(
        _siteConfig.baseUrl,
      );
      if (specialMapping.isNotEmpty) {
        _discountMapping?.addAll(specialMapping);
      }
    } catch (e) {
      _discountMapping = {};
    }
  }

  /// 加载标签映射配置
  Future<void> _loadTagMapping() async {
    try {
      final template = await SiteConfigService.getTemplateById(
        '',
        SiteType.mteam,
      );
      if (template?.tagMapping != null) {
        _tagMapping = Map<String, String>.from(template!.tagMapping);
      }
    } catch (e) {
      _tagMapping = {};
    }
  }

  /// 从字符串解析标签类型
  TagType? _parseTagType(String? str) {
    if (str == null || str.isEmpty) return null;

    final mapping = _tagMapping ?? {};
    final enumName = mapping[str];

    if (enumName != null) {
      for (final type in TagType.values) {
        if (type.name.toLowerCase() == enumName.toLowerCase()) {
          return type;
        }
        if (type.content == enumName) {
          return type;
        }
      }
    }
    return null;
  }

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(String? str) {
    if (str == null || str.isEmpty) return DiscountType.normal;

    final mapping = _discountMapping ?? {};
    final enumValue = mapping[str];

    if (enumValue != null) {
      for (final type in DiscountType.values) {
        if (type.value == enumValue) {
          return type;
        }
      }
    }

    return DiscountType.normal;
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    final resp = await _dio.post(
      '/api/member/profile',
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Profile fetch failed',
      );
    }
    // 先解析基础资料
    final baseProfile = _parseMemberProfile(data['data'] as Map<String, dynamic>);

    // 追加获取时魔（每小时魔力增长）与做种体积（字节）
    double? bonusPerHour;
    int? seedingSizeBytes;

    try {
      final bonusResp = await _dio.post('/api/tracker/mybonus');
      final bonusData = bonusResp.data as Map<String, dynamic>;
      if (bonusData['code']?.toString() == '0') {
        final formulaParams = (bonusData['data'] as Map<String, dynamic>?)?['formulaParams'] as Map<String, dynamic>?;
        final finalBs = formulaParams?['finalBs'];
        if (finalBs != null) {
          bonusPerHour = double.tryParse(finalBs.toString());
        }
      }
    } catch (_) {
      // 忽略错误，保持为null
    }

    try {
      final seedResp = await _dio.post('/api/tracker/myPeerStatistics');
      final seedData = seedResp.data as Map<String, dynamic>;
      if (seedData['code']?.toString() == '0') {
        final seederSize = (seedData['data'] as Map<String, dynamic>?)?['seederSize'];
        if (seederSize != null) {
          seedingSizeBytes = int.tryParse(seederSize.toString());
        }
      }
    } catch (_) {
      // 忽略错误，保持为null
    }

    return MemberProfile(
      username: baseProfile.username,
      bonus: baseProfile.bonus,
      shareRate: baseProfile.shareRate,
      uploadedBytes: baseProfile.uploadedBytes,
      downloadedBytes: baseProfile.downloadedBytes,
      uploadedBytesString: baseProfile.uploadedBytesString,
      downloadedBytesString: baseProfile.downloadedBytesString,
      userId: baseProfile.userId,
      passKey: baseProfile.passKey,
      lastAccess: baseProfile.lastAccess,
      bonusPerHour: bonusPerHour,
      seedingSizeBytes: seedingSizeBytes,
    );
  }

  /// 解析 M-Team 站点的用户资料数据
  MemberProfile _parseMemberProfile(Map<String, dynamic> json) {
    final mc = json['memberCount'] as Map<String, dynamic>?;
    final memberStatus = json['memberStatus'] as Map<String, dynamic>?;
    double parseDouble(dynamic v) =>
        v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;

    final uploadedBytes = parseInt(mc?['uploaded']);
    final downloadedBytes = parseInt(mc?['downloaded']);

    return MemberProfile(
      username: (json['username'] ?? '').toString(),
      bonus: parseDouble(mc?['bonus']),
      shareRate: parseDouble(mc?['shareRate']),
      uploadedBytes: uploadedBytes,
      downloadedBytes: downloadedBytes,
      uploadedBytesString: Formatters.dataFromBytes(uploadedBytes),
      downloadedBytesString: Formatters.dataFromBytes(downloadedBytes),
      passKey: null, // M-Team类型不提供passKey
      lastAccess: memberStatus?['lastBrowse']?.toString(),
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
    final requestData = <String, Object>{
      'visible': 1,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (keyword != null && keyword.trim().isNotEmpty)
        'keyword': keyword.trim(),
      if (onlyFav != null) 'onlyFav': onlyFav,
    };

    // 合并额外参数
    if (additionalParams != null) {
      additionalParams.forEach((key, value) {
        requestData[key] = value;
      });
    }

    final resp = await _dio.post(
      '/api/torrent/search',
      data: requestData,
      options: Options(contentType: 'application/json'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Search failed',
      );
    }

    final searchData = data['data'] as Map<String, dynamic>;
    final rawList = (searchData['data'] as List? ?? []);

    Map<String, dynamic> historyMap = {};
    Map<String, dynamic> peerMap = {};

    // Query download history for all torrent IDs
    if (rawList.isNotEmpty) {
      try {
        final tids = rawList.map((e) => (e['id'] ?? '').toString()).toList();
        final historyData = await queryHistory(tids: tids);
        historyMap = historyData['historyMap'] as Map<String, dynamic>? ?? {};
        peerMap = historyData['peerMap'] as Map<String, dynamic>? ?? {};
      } catch (e) {
        // If history query fails, continue with empty history
      }
    }

    return _parseTorrentSearchResult(
      searchData,
      historyMap: historyMap,
      peerMap: peerMap,
    );
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    final formData = FormData.fromMap({'id': id});

    final resp = await _dio.post(
      '/api/torrent/detail',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Fetch detail failed',
      );
    }

    return _parseTorrentDetail(data['data'] as Map<String, dynamic>);
  }

  /// 解析 M-Team 站点的种子详情数据
  TorrentDetail _parseTorrentDetail(Map<String, dynamic> json) {
    return TorrentDetail(descr: (json['descr'] ?? '').toString());
  }

  /// 解析 M-Team 站点的种子搜索结果数据
  TorrentSearchResult _parseTorrentSearchResult(
    Map<String, dynamic> json, {
    Map<String, dynamic>? historyMap,
    Map<String, dynamic>? peerMap,
  }) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    final list = (json['data'] as List? ?? const []).cast<dynamic>();
    return TorrentSearchResult(
      pageNumber: parseInt(json['pageNumber']),
      pageSize: parseInt(json['pageSize']),
      total: parseInt(json['total']),
      totalPages: parseInt(json['totalPages']),
      items: list
          .map(
            (e) => _parseTorrentItem(
              e as Map<String, dynamic>,
              historyMap: historyMap,
              peerMap: peerMap,
            ),
          )
          .toList(),
    );
  }

  /// 解析 M-Team 站点的种子项目数据
  TorrentItem _parseTorrentItem(
    Map<String, dynamic> json, {
    Map<String, dynamic>? historyMap,
    Map<String, dynamic>? peerMap,
  }) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    bool parseBool(dynamic v) =>
        v == true || v.toString().toLowerCase() == 'true';
    final status = (json['status'] as Map<String, dynamic>?) ?? const {};
    final promotionRule =
        (status['promotionRule'] as Map<String, dynamic>?) ?? const {};
    final imgs =
        (json['imageList'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];

    // 优先使用promotionRule中的字段，如果不存在则使用status中的字段
    var discount =
        promotionRule['discount']?.toString() ?? status['discount']?.toString();
    var discountEndTime =
        promotionRule['endTime']?.toString() ??
        status['discountEndTime']?.toString();
    final toppingLevel = int.tryParse(status['toppingLevel']?.toString() ?? '');
    final toppingEndTime = status['toppingEndTime']?.toString();
    if (toppingLevel != null && toppingLevel == 1) {
      discount = "FREE";
      discountEndTime = toppingEndTime;
    }
    // if ((discount ?? '').toUpperCase() == 'FREE') {
    //   discountEndTime =
    //       Formatters.laterDateTime(discountEndTime, toppingEndTime) ?? '';
    // }

    final name = (json['name'] ?? '').toString();
    final smallDescr = (json['smallDescr'] ?? '').toString();

    // 1. 从 name 中提取标签
    // 1. 从 name 中提取标签
    final nameTags = TagType.matchTags(name);

    // 2. 从 labelsNew 中提取标签
    final labelsNew = json['labelsNew'];
    if (labelsNew is List) {
      for (var label in labelsNew) {
        final labelStr = label.toString();
        // 尝试映射标签
        final mapped = _parseTagType(labelStr);
        if (mapped != null && !nameTags.contains(mapped)) {
          nameTags.add(mapped);
        }
      }
    }


    final id = (json['id'] ?? '').toString();
    DownloadStatus downloadStatus = DownloadStatus.none;
    if (historyMap != null && historyMap.containsKey(id)) {
      final history = historyMap[id] as Map<String, dynamic>;
      final timesCompleted =
          int.tryParse(history['timesCompleted']?.toString() ?? '0') ?? 0;
      if (timesCompleted > 0) {
        downloadStatus = DownloadStatus.completed;
      } else if (peerMap != null && peerMap.containsKey(id)) {
        downloadStatus = DownloadStatus.downloading;
      }
    }

    return TorrentItem(
      id: id,
      name: name,
      smallDescr: smallDescr, // 使用原始描述
      discount: _parseDiscountType(discount),
      discountEndTime: discountEndTime,
      downloadUrl: null,
      seeders: parseInt(status['seeders']),
      leechers: parseInt(status['leechers']),
      sizeBytes: parseInt(json['size']),
      imageList: imgs,
      cover: imgs.isNotEmpty ? imgs.first : '',
      downloadStatus: downloadStatus,
      collection: parseBool(json['collection']),
      createdDate: json['createdDate'] ?? '',
      doubanRating: (json['doubanRating'] ?? 'N/A').toString(),
      imdbRating: (json['imdbRating'] ?? 'N/A').toString(),
      isTop: (toppingLevel ?? 0) > 0,
      tags: nameTags,
    );
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    final form = FormData.fromMap({'id': id});
    final resp = await _dio.post(
      '/api/torrent/genDlToken',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'genDlToken failed',
      );
    }
    final url = (data['data'] ?? '').toString();
    if (url.isEmpty) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: 'Empty download url',
      );
    }
    return url;
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    final resp = await _dio.post(
      '/api/tracker/queryHistory',
      data: {'tids': tids},
      options: Options(contentType: 'application/json'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Query history failed',
      );
    }
    return data['data'] as Map<String, dynamic>;
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
    final formData = FormData.fromMap({'id': torrentId, 'make': make});

    final resp = await _dio.post(
      '/api/torrent/collection',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Toggle collection failed',
      );
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
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 从JSON配置文件中加载默认的分类配置，通过baseUrl匹配
    return await SiteConfigService.getDefaultSearchCategories(
      _siteConfig.baseUrl,
    );
  }
}
