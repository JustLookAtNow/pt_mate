import 'dart:async';

import 'package:dio/dio.dart';

import '../../models/app_models.dart';
import '../storage/storage_service.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {
      'accept': 'application/json, text/plain, */*',
      'user-agent': 'MTeamApp/1.0 (Flutter; Dio)',
    },
  ));

  SiteConfig? _site;

  Future<void> init() async {
    _site = await StorageService.instance.loadSite();

    _dio.interceptors.clear();
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      // Prefer per-request site override if provided via extra
      SiteConfig? site = options.extra['siteOverride'] is SiteConfig
          ? options.extra['siteOverride'] as SiteConfig
          : _site;
      // ensure latest site is available when not overridden
      if (site == null) {
        site = await StorageService.instance.loadSite();
        _site = site;
      }

      // if request didn't set baseUrl explicitly, apply saved base (normalize trailing slash)
      if ((options.baseUrl.isEmpty || options.baseUrl == '/') && site != null) {
        var base = site.baseUrl.trim();
        if (base.endsWith('/')) base = base.substring(0, base.length - 1);
        options.baseUrl = base;
      }

      // apply auth header only when caller didn't provide one (respect explicit override)
      final hasExplicitKey = options.headers.containsKey('x-api-key') &&
          ((options.headers['x-api-key']?.toString().isNotEmpty) == true);
      final siteKey = site?.apiKey ?? '';
      if (!hasExplicitKey && siteKey.isNotEmpty) {
        options.headers['x-api-key'] = siteKey;
      }

      return handler.next(options);
    }));
  }

  // Member profile - use relative path, rely on saved baseUrl and x-api-key from interceptor
  // Allows overriding apiKey and/or site for one-off test on login page
  Future<MemberProfile> fetchMemberProfile({String? apiKey, SiteConfig? siteOverride}) async {
    final key = apiKey; // if null, interceptor will add saved x-api-key

    // final formData = FormData.fromMap({
    //   '_timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
    //   // _sgin 如服务端有要求，后续在掌握算法后补充
    // });

    final resp = await _dio.post(
      '/api/member/profile',
      // data: formData,
      options: Options(
        headers: (key != null && key.isNotEmpty) ? {'x-api-key': key} : null,
        extra: {
          if (siteOverride != null) 'siteOverride': siteOverride,
        },
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(requestOptions: resp.requestOptions, response: resp, error: data['message'] ?? 'Profile fetch failed');
    }
    return MemberProfile.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// 获取种子详情
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

  // Search torrents - relative path, baseUrl from saved site, auth via interceptor
  Future<TorrentSearchResult> searchTorrents({
    required String mode, // normal, tvshow, movie, adult
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
  }) async {
    final resp = await _dio.post(
      '/api/torrent/search',
      data: {
        'mode': mode,
        'visible': 1,
        'categories': [],
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (keyword != null && keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (onlyFav != null) 'onlyFav': onlyFav,
      },
      options: Options(contentType: 'application/json'),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['code']?.toString() != '0') {
      throw DioException(requestOptions: resp.requestOptions, response: resp, error: data['message'] ?? 'Search failed');
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

  // Generate download token and return final download URL
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

  // Query download history for multiple torrent IDs
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

  // Toggle torrent collection status
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
}

class MemberProfile {
  final String username;
  final double bonus; // magic points
  final double shareRate;
  final int uploadedBytes;
  final int downloadedBytes;

  MemberProfile({
    required this.username,
    required this.bonus,
    required this.shareRate,
    required this.uploadedBytes,
    required this.downloadedBytes,
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    final mc = json['memberCount'] as Map<String, dynamic>?;
    double parseDouble(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    return MemberProfile(
      username: (json['username'] ?? '').toString(),
      bonus: parseDouble(mc?['bonus']),
      shareRate: parseDouble(mc?['shareRate']),
      uploadedBytes: parseInt(mc?['uploaded']),
      downloadedBytes: parseInt(mc?['downloaded']),
    );
  }
}

class TorrentDetail {
  final String descr;
  
  TorrentDetail({required this.descr});
  
  factory TorrentDetail.fromJson(Map<String, dynamic> json) {
    return TorrentDetail(
      descr: (json['descr'] ?? '').toString(),
    );
  }
}

enum DownloadStatus {
  none,        // 未下载
  downloading, // 下载中
  completed,   // 已完成
}

class TorrentItem {
  final String id;
  final String name;
  final String smallDescr;
  final String? discount; // e.g., FREE, PERCENT_50
  final String? discountEndTime; // e.g., 2025-08-27 21:16:48
  final int seeders;
  final int leechers;
  final int sizeBytes;
  final List<String> imageList;
  final DownloadStatus downloadStatus;
  final bool collection; // 是否已收藏

  TorrentItem({
    required this.id,
    required this.name,
    required this.smallDescr,
    required this.discount,
    required this.discountEndTime,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.imageList,
    this.downloadStatus = DownloadStatus.none,
    this.collection = false,
  });

  factory TorrentItem.fromJson(Map<String, dynamic> json, {DownloadStatus? downloadStatus}) {
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
      discount: discount,
      discountEndTime: discountEndTime,
      seeders: parseInt(status['seeders']),
      leechers: parseInt(status['leechers']),
      sizeBytes: parseInt(json['size']),
      imageList: imgs,
      downloadStatus: downloadStatus ?? DownloadStatus.none,
      collection: parseBool(json['collection']),
    );
  }
}

class TorrentSearchResult {
  final int pageNumber;
  final int pageSize;
  final int total;
  final int totalPages;
  final List<TorrentItem> items;

  TorrentSearchResult({
    required this.pageNumber,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.items,
  });

  factory TorrentSearchResult.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    final list = (json['data'] as List? ?? const []).cast<dynamic>();
    return TorrentSearchResult(
      pageNumber: parseInt(json['pageNumber']),
      pageSize: parseInt(json['pageSize']),
      total: parseInt(json['total']),
      totalPages: parseInt(json['totalPages']),
      items: list.map((e) => TorrentItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}