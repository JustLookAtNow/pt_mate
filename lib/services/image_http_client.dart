import 'package:dio/dio.dart';

class ImageHttpClient {
  ImageHttpClient._();
  static final ImageHttpClient instance = ImageHttpClient._();

  // 缓存配置
  static const int _maxCacheSize = 500; // 最大缓存图片数量
  static const int _maxCacheSizeBytes = 100 * 1024 * 1024; // 最大缓存大小 100MB

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
  );

  // 内存缓存，存储图片数据
  final Map<String, List<int>> _imageCache = {};

  // LRU访问顺序记录，最近访问的在最后
  final List<String> _accessOrder = [];

  // 正在请求的Future缓存，避免重复请求
  final Map<String, Future<Response<List<int>>>> _pendingRequests = {};

  /// 获取图片数据（带缓存）
  Future<Response<List<int>>> fetchImage(
    String url, {
    String? siteBaseUrl,
    String? siteCookie,
  }) async {
    final cacheKey = _buildCacheKey(
      url,
      siteBaseUrl: siteBaseUrl,
      siteCookie: siteCookie,
    );

    // 如果缓存中已有数据，更新访问顺序并返回
    if (_imageCache.containsKey(cacheKey)) {
      _updateAccessOrder(cacheKey);
      return Response<List<int>>(
        data: _imageCache[cacheKey],
        statusCode: 200,
        requestOptions: RequestOptions(path: url),
      );
    }

    // 如果正在请求中，返回相同的Future
    if (_pendingRequests.containsKey(cacheKey)) {
      return _pendingRequests[cacheKey]!;
    }

    // 创建新的请求
    final future = _fetchImageFromNetwork(
      url,
      siteBaseUrl: siteBaseUrl,
      siteCookie: siteCookie,
    );
    _pendingRequests[cacheKey] = future;

    try {
      final response = await future;
      // 请求成功，缓存数据
      if (response.data != null && response.statusCode == 200) {
        _addToCache(cacheKey, response.data!);
      }
      return response;
    } catch (e) {
      // 请求失败，移除可能存在的损坏缓存
      _removeFromCache(cacheKey);
      rethrow;
    } finally {
      // 请求完成，移除pending状态
      _pendingRequests.remove(cacheKey);
    }
  }

  /// 从网络获取图片数据
  Future<Response<List<int>>> _fetchImageFromNetwork(
    String url, {
    String? siteBaseUrl,
    String? siteCookie,
  }) async {
    final shouldAttachCookie = _shouldAttachSiteCookie(
      url,
      siteBaseUrl: siteBaseUrl,
    );

    // 根据不同的图片域名设置不同的Referer
    String? referer;
    if (siteBaseUrl != null && siteBaseUrl.trim().isNotEmpty) {
      referer = _normalizeBaseUrl(siteBaseUrl);
    } else if (url.contains('doubanio.com')) {
      referer = 'https://www.douban.com/';
    } else if (url.contains('m-team.cc')) {
      referer = 'https://kp.m-team.cc/';
    } else {
      // 从URL中提取主域名作为referer
      final uri = Uri.parse(url);
      referer = '${uri.scheme}://${uri.host}/';
    }

    return await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Referer': referer,
          if (shouldAttachCookie &&
              siteCookie != null &&
              siteCookie.trim().isNotEmpty)
            'Cookie': siteCookie,
        },
      ),
    );
  }

  String _buildCacheKey(String url, {String? siteBaseUrl, String? siteCookie}) {
    final shouldAttachCookie = _shouldAttachSiteCookie(
      url,
      siteBaseUrl: siteBaseUrl,
    );
    final normalizedBaseUrl = _normalizeBaseUrl(siteBaseUrl);
    final cookieFingerprint =
        shouldAttachCookie && siteCookie != null && siteCookie.trim().isNotEmpty
        ? siteCookie.hashCode
        : 0;
    return '$url|$normalizedBaseUrl|$cookieFingerprint';
  }

  String _normalizeBaseUrl(String? baseUrl) {
    final normalized = baseUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }

  bool _shouldAttachSiteCookie(String url, {String? siteBaseUrl}) {
    final normalizedBaseUrl = _normalizeBaseUrl(siteBaseUrl);
    if (normalizedBaseUrl.isEmpty) {
      return false;
    }

    try {
      final imageUri = Uri.parse(url);
      final siteUri = Uri.parse(normalizedBaseUrl);
      final imageHost = imageUri.host.toLowerCase();
      final siteHost = siteUri.host.toLowerCase();

      if (imageHost.isEmpty || siteHost.isEmpty) {
        return false;
      }

      if (imageHost == siteHost) {
        return true;
      }

      if (imageHost.endsWith('.$siteHost') ||
          siteHost.endsWith('.$imageHost')) {
        return true;
      }

      final imageRootDomain = _rootDomain(imageHost);
      final siteRootDomain = _rootDomain(siteHost);
      return imageRootDomain.isNotEmpty && imageRootDomain == siteRootDomain;
    } catch (_) {
      return false;
    }
  }

  String _rootDomain(String host) {
    final segments = host.split('.');
    if (segments.length < 2) {
      return host;
    }
    return '${segments[segments.length - 2]}.${segments.last}';
  }

  /// 更新访问顺序（LRU）
  void _updateAccessOrder(String url) {
    _accessOrder.remove(url);
    _accessOrder.add(url);
  }

  /// 添加到缓存，自动管理缓存大小
  void _addToCache(String url, List<int> data) {
    // 检查是否需要清理缓存
    _evictIfNeeded();

    // 添加新数据
    _imageCache[url] = data;
    _updateAccessOrder(url);
  }

  /// 从缓存中移除
  void _removeFromCache(String url) {
    _imageCache.remove(url);
    _accessOrder.remove(url);
  }

  /// 检查并清理缓存（LRU策略）
  void _evictIfNeeded() {
    // 检查数量限制
    while (_imageCache.length >= _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }

    // 检查大小限制
    while (_getCurrentCacheSize() > _maxCacheSizeBytes) {
      _evictLeastRecentlyUsed();
    }
  }

  /// 清理最久未使用的缓存项
  void _evictLeastRecentlyUsed() {
    if (_accessOrder.isNotEmpty) {
      final oldestUrl = _accessOrder.removeAt(0);
      _imageCache.remove(oldestUrl);
    }
  }

  /// 获取当前缓存大小（字节）
  int _getCurrentCacheSize() {
    int totalSize = 0;
    for (final data in _imageCache.values) {
      totalSize += data.length;
    }
    return totalSize;
  }

  /// 清理图片缓存
  void clearCache() {
    _imageCache.clear();
    _accessOrder.clear();
  }

  /// 获取缓存大小（图片数量）
  int getCacheSize() {
    return _imageCache.length;
  }

  /// 获取缓存大小（字节数）
  int getCacheSizeBytes() {
    return _getCurrentCacheSize();
  }

  /// 移除特定URL的缓存
  void removeCacheForUrl(String url) {
    final keys = _imageCache.keys
        .where((key) => key.startsWith('$url|'))
        .toList();
    for (final key in keys) {
      _removeFromCache(key);
    }
  }
}
