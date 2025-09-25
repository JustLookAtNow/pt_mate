import 'package:dio/dio.dart';
import '../../models/app_models.dart';
import '../site_config_service.dart';
import 'site_adapter.dart';
import '../../utils/format.dart';

/// M-Team站点适配器实现
class MTeamAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  Map<String, String>? _discountMapping;
  
  @override
  SiteConfig get siteConfig => _siteConfig;
  
  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;
    
    // 加载优惠类型映射配置
    await _loadDiscountMapping();
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'accept': 'application/json, text/plain, */*',
        'user-agent': 'MTeamApp/1.0 (Flutter; Dio)',
      },
    ));
    
    _dio.interceptors.clear();
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      // 设置baseUrl
      if (options.baseUrl.isEmpty || options.baseUrl == '/') {
        var base = _siteConfig.baseUrl.trim();
        if (base.endsWith('/')) base = base.substring(0, base.length - 1);
        options.baseUrl = base;
      }
      
      // 设置API密钥
      final hasExplicitKey = options.headers.containsKey('x-api-key') &&
          ((options.headers['x-api-key']?.toString().isNotEmpty) == true);
      final siteKey = _siteConfig.apiKey ?? '';
      if (!hasExplicitKey && siteKey.isNotEmpty) {
        options.headers['x-api-key'] = siteKey;
      }
      
      return handler.next(options);
    }));
  }
  
  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
      final template = await SiteConfigService.getDefaultTemplate('M-Team');
      if (template != null && template['discountMapping'] != null) {
        _discountMapping = Map<String, String>.from(template['discountMapping']);
      }
      final specialMapping = await SiteConfigService.getDiscountMapping(_siteConfig.baseUrl);
      if (specialMapping.isNotEmpty) {
        _discountMapping?.addAll(specialMapping);
      }
    } catch (e) {
      _discountMapping = {};
    }
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
      options: Options(
        headers: (apiKey != null && apiKey.isNotEmpty) ? {'x-api-key': apiKey} : null,
      ),
    );
    
    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        error: data['message'] ?? 'Profile fetch failed',
      );
    }
    return _parseMemberProfile(data['data'] as Map<String, dynamic>);
  }

  /// 解析 M-Team 站点的用户资料数据
  MemberProfile _parseMemberProfile(Map<String, dynamic> json) {
    final mc = json['memberCount'] as Map<String, dynamic>?;
    double parseDouble(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
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
      if (keyword != null && keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
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
    
    final searchResult = _parseTorrentSearchResult(data['data'] as Map<String, dynamic>);
    
    // Query download history for all torrent IDs
    if (searchResult.items.isNotEmpty) {
      try {
        final tids = searchResult.items.map((item) => item.id).toList();
        final historyData = await queryHistory(tids: tids);
        final historyMap = historyData['historyMap'] as Map<String, dynamic>? ?? {};
        final peerMap = historyData['peerMap'] as Map<String, dynamic>? ?? {};
        
        // Update items with download status
        final updatedItems = searchResult.items.map((item) {
          DownloadStatus status = DownloadStatus.none;
          if (historyMap.containsKey(item.id)) {
            final history = historyMap[item.id] as Map<String, dynamic>;
            final timesCompleted = int.tryParse(history['timesCompleted']?.toString() ?? '0') ?? 0;
            if (timesCompleted > 0) {
              status = DownloadStatus.completed;
            } else if (peerMap.containsKey(item.id)) {
              status = DownloadStatus.downloading;
            } else {
              status = DownloadStatus.none;
            }
          }
          return TorrentItem(
            id: item.id,
            name: item.name,
            smallDescr: item.smallDescr,
            discount: item.discount,
            discountEndTime: item.discountEndTime,
            downloadUrl: item.downloadUrl,
            seeders: item.seeders,
            leechers: item.leechers,
            sizeBytes: item.sizeBytes,
            imageList: item.imageList,
            cover: item.imageList.isNotEmpty ? item.imageList.first : '',
            downloadStatus: status,
            collection: item.collection,
          );
        }).toList();
        
        return TorrentSearchResult(
          pageNumber: searchResult.pageNumber,
          pageSize: searchResult.pageSize,
          total: searchResult.total,
          totalPages: searchResult.totalPages,
          items: updatedItems,
        );
      } catch (e) {
        // If history query fails, return original result without download status
        return searchResult;
      }
    }
    
    return searchResult;
  }
  
  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    final formData = FormData.fromMap({
      'id': id,
    });
    
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
    return TorrentDetail(
      descr: (json['descr'] ?? '').toString(),
    );
  }

  /// 解析 M-Team 站点的种子搜索结果数据
  TorrentSearchResult _parseTorrentSearchResult(Map<String, dynamic> json) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    final list = (json['data'] as List? ?? const []).cast<dynamic>();
    return TorrentSearchResult(
      pageNumber: parseInt(json['pageNumber']),
      pageSize: parseInt(json['pageSize']),
      total: parseInt(json['total']),
      totalPages: parseInt(json['totalPages']),
      items: list.map((e) => _parseTorrentItem(e as Map<String, dynamic>)).toList(),
    );
  }

  /// 解析 M-Team 站点的种子项目数据
  TorrentItem _parseTorrentItem(Map<String, dynamic> json, {DownloadStatus? downloadStatus}) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    bool parseBool(dynamic v) => v == true || v.toString().toLowerCase() == 'true';
    final status = (json['status'] as Map<String, dynamic>?) ?? const {};
    final promotionRule = (status['promotionRule'] as Map<String, dynamic>?) ?? const {};
    final imgs = (json['imageList'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    
    // 优先使用promotionRule中的字段，如果不存在则使用status中的字段
    final discount = promotionRule['discount']?.toString() ?? status['discount']?.toString();
    final discountEndTime = promotionRule['endTime']?.toString() ?? status['discountEndTime']?.toString();
    
    return TorrentItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      smallDescr: (json['smallDescr'] ?? '').toString(),
      discount: _parseDiscountType(discount),
      discountEndTime: discountEndTime,
      downloadUrl: null,
      seeders: parseInt(status['seeders']),
      leechers: parseInt(status['leechers']),
      sizeBytes: parseInt(json['size']),
      imageList: imgs,
      cover: imgs.isNotEmpty ? imgs.first : '',
      downloadStatus: downloadStatus ?? DownloadStatus.none,
      collection: parseBool(json['collection']),
    );
  }
  
  @override
  Future<String> genDlToken({required String id}) async {
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
  Future<Map<String, dynamic>> queryHistory({required List<String> tids}) async {
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
  Future<void> toggleCollection({required String id, required bool make}) async {
    final formData = FormData.fromMap({
      'id': id,
      'make': make,
    });
    
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
    // 从JSON配置文件中加载默认的分类配置，优先匹配baseUrl，然后类型
    return await SiteConfigService.getDefaultSearchCategories(
      _siteConfig.siteType.id,
      baseUrl: _siteConfig.baseUrl,
    );
  }
}