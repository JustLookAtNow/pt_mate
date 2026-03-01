import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../models/app_models.dart';
import 'api_exceptions.dart';
import 'site_adapter.dart';

/// UNIT3D 站点适配器
/// 适配 UNIT3D 架构的 PT 站点 API
class Unit3dAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  static final Logger _logger = Logger();

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    final swTotal = Stopwatch()..start();
    _siteConfig = config;

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
    _dio.options.headers['Accept'] = 'application/json';

    // 设置 API 授权
    if (_siteConfig.apiKey != null && _siteConfig.apiKey!.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer ${_siteConfig.apiKey}';
    } else {
      _logger.w('Unit3dAdapter: API Key is missing for ${_siteConfig.name}');
    }

    swTotal.stop();
    _logger.d('Unit3dAdapter.init: 总耗时=${swTotal.elapsedMilliseconds}ms');
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      if (apiKey != null && apiKey.isNotEmpty) {
        _dio.options.headers['Authorization'] = 'Bearer $apiKey';
      }

      final response = await _dio.get('/api/users');

      if (response.statusCode == 200 && response.data != null) {
        var userData = response.data['data']?[0];
        if (response.data['data'] is List) {
           for(var user in response.data['data']) {
             if(user['is_me'] == true) {
                 userData = user;
                 break;
             }
           }
        }

        if (userData == null) {
          throw const SiteServiceException(message: '未找到当前用户数据');
        }

        final uploaded = (userData['uploaded'] as num?)?.toInt() ?? 0;
        final downloaded = (userData['downloaded'] as num?)?.toInt() ?? 0;

        return MemberProfile(
          userId: userData['id']?.toString() ?? '',
          username: userData['username'] ?? 'Unknown',
          bonus: 0.0,
          shareRate: (userData['ratio'] as num?)?.toDouble() ?? 0.0,
          uploadedBytes: uploaded,
          downloadedBytes: downloaded,
          uploadedBytesString: uploaded.toString(),
          downloadedBytesString: downloaded.toString()
        );
      } else {
        throw SiteServiceException(
          message: '获取用户资料失败: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取用户资料');
    }
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
      final queryParams = <String, dynamic>{
        'page': pageNumber,
        'perPage': pageSize,
      };

      if (keyword != null && keyword.isNotEmpty) {
        queryParams['name'] = keyword;
      }

      if (additionalParams != null) {
        additionalParams.forEach((key, value) {
          if (value != null) {
            queryParams[key] = value;
          }
        });
      }

      final response = await _dio.get('/api/torrents/filter', queryParameters: queryParams);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final torrents = <TorrentItem>[];

        if (data['data'] is List) {
          for (var item in data['data']) {
            torrents.add(_parseTorrentItem(item));
          }
        }

        final meta = data['meta'] ?? {};
        final totalCount = meta['total'] as int? ?? 0;
        final lastPage = meta['last_page'] as int? ?? 1;

        return TorrentSearchResult(
          items: torrents,
          total: totalCount,
          totalPages: lastPage,
          pageNumber: pageNumber,
          pageSize: pageSize,
        );
      } else {
        throw SiteServiceException(
          message: '搜索种子失败: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '搜索种子');
    }
  }

  TorrentItem _parseTorrentItem(Map<String, dynamic> item) {
    String title = item['name'] ?? '';

    DateTime publishDate = DateTime.now();
    if (item['created_at'] != null) {
      try {
        publishDate = DateTime.parse(item['created_at']);
      } catch (_) {}
    }

    DiscountType discount = DiscountType.normal;
    if (item['freeleech'] == true) {
       discount = DiscountType.free;
    } else if (item['doubleup'] == true) {
       discount = DiscountType.twoXFree;
    }

    List<TagType> tags = [];

    return TorrentItem(
      id: item['id']?.toString() ?? '',
      name: title,
      smallDescr: '',
      sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
      createdDate: publishDate,
      seeders: (item['seeders'] as num?)?.toInt() ?? 0,
      leechers: (item['leechers'] as num?)?.toInt() ?? 0,
      discount: discount,
      discountEndTime: null,
      tags: tags,
      cover: item['poster'] ?? '',
      imageList: [],
      downloadStatus: DownloadStatus.none,
      collection: false,
      isTop: false,
      comments: 0,
      downloadUrl: item['download_link'] ?? '${_siteConfig.baseUrl}/api/torrents/download/${item['id']}',
    );
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
     try {
       final response = await _dio.get('/api/torrents/$id');

       if (response.statusCode == 200 && response.data != null) {
           final data = response.data['data'] ?? response.data;

           return TorrentDetail(
              descr: data['description'] ?? '',
              descrHtml: data['description'] ?? '',
           );
       } else {
           throw SiteServiceException(message: '获取种子详情失败');
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
    return TorrentCommentList(
      comments: [],
      total: 0,
      pageNumber: pageNumber,
      pageSize: pageSize,
      totalPages: 1,
    );
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http')) return url;
      return '${_siteConfig.baseUrl}$url';
    }

    return '${_siteConfig.baseUrl}/api/torrents/download/$id';
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    return {};
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
     throw const SiteServiceException(message: '当前站点不支持通过 API 收藏');
  }

  @override
  Future<bool> testConnection() async {
    try {
      await fetchMemberProfile();
      return true;
    } catch (e) {
      _logger.e('Unit3dAdapter.testConnection error', error: e);
      return false;
    }
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
     try {
       final response = await _dio.get('/api/categories');
       if(response.statusCode == 200 && response.data != null) {
           List<SearchCategoryConfig> categories = [];
           var data = response.data;
           if(data['data'] is List) {
               for(var cat in data['data']) {
                   categories.add(SearchCategoryConfig(
                       id: cat['id'].toString(),
                       displayName: cat['name'] ?? '',
                       parameters: 'categories[]=${cat['id']}',
                   ));
               }
           }
           return categories;
       }
       return [];
     } catch(e) {
       _logger.e('Unit3dAdapter.getSearchCategories error', error: e);
       return [];
     }
  }
}
