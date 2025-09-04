import 'package:dio/dio.dart';
import '../../models/app_models.dart';
import 'site_adapter.dart';
import 'api_client.dart';

/// M-Team站点适配器实现
class MTeamAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  
  @override
  SiteConfig get siteConfig => _siteConfig;
  
  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
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
    return MemberProfile.fromJson(data['data'] as Map<String, dynamic>);
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
    
    final searchResult = TorrentSearchResult.fromJson(data['data'] as Map<String, dynamic>);
    
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
            seeders: item.seeders,
            leechers: item.leechers,
            sizeBytes: item.sizeBytes,
            imageList: item.imageList,
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
    
    return TorrentDetail.fromJson(data['data'] as Map<String, dynamic>);
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
}