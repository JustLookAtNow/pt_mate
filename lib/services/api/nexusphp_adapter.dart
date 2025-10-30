import 'package:dio/dio.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../models/app_models.dart';
import 'site_adapter.dart';
import '../site_config_service.dart';
import '../../utils/format.dart';

/// NexusPHP 站点适配器
/// 实现 NexusPHP (1.9+) 站点的 API 调用
class NexusPHPAdapter implements SiteAdapter {
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

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
        headers: _buildHeaders(config.apiKey),
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

          return handler.next(options);
        },
      ),
    );
  }

  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
      final template = await SiteConfigService.getTemplateById(
        '',
        SiteType.nexusphp,
      );
      if (template?.discountMapping != null) {
        _discountMapping = Map<String, String>.from(
          template!.discountMapping,
        );
      }
      final specialMapping = await SiteConfigService.getDiscountMapping(
        _siteConfig.baseUrl,
      );
      if (specialMapping.isNotEmpty) {
        _discountMapping?.addAll(specialMapping);
      }
    } catch (e) {
      // 使用默认映射
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

  /// 构建请求头，包含Bearer Token认证
  Map<String, String> _buildHeaders(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final response = await _dio.get('/api/v1/profile');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['ret'] == 0 && data['data'] != null) {
          return _parseMemberProfile(data['data']['data']);
        } else {
          throw Exception('API返回错误: ${data['msg']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('获取用户资料失败: $e');
    }
  }

  /// 解析用户资料数据
  MemberProfile _parseMemberProfile(Map<String, dynamic> data) {
    final uploadedBytes = (data['uploaded'] ?? 0).toInt();
    final downloadedBytes = (data['downloaded'] ?? 0).toInt();

    return MemberProfile(
      username: data['username'] ?? '',
      bonus: (data['bonus'] ?? 0).toDouble(),
      shareRate: double.tryParse(data['share_ratio']?.toString() ?? '0') ?? 0.0,
      uploadedBytes: uploadedBytes,
      downloadedBytes: downloadedBytes,
      uploadedBytesString: Formatters.dataFromBytes(uploadedBytes),
      downloadedBytesString: Formatters.dataFromBytes(downloadedBytes),
      userId: data['id']?.toString(), // 从data.data.id获取用户ID
      passKey: null, // NexusPHP API类型不提供passKey
      lastAccess: data['last_access']?.toString(),
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
      'page': pageNumber.toString(),
      'per_page': pageSize.toString(),
      'include_fields[torrent]': 'download_url,has_bookmarked',
    };

    if (keyword != null && keyword.isNotEmpty) {
      params['filter[title]'] = keyword;
    }
    if (onlyFav != null && onlyFav > 0) {
      params['filter[bookmark]'] = onlyFav;
    }
    var url = '/api/v1/torrents';
    // 添加额外参数
    if (additionalParams != null && additionalParams.isNotEmpty) {
      //
      for (var add in additionalParams.entries) {
        if (add.key == 'category') {
          var category = add.value.toString().split('#');
          if (category.length == 2) {
            url += '/${category[0]}';
            params['filter[category]'] = category[1];
          }
        } else {
          params[add.key] = add.value;
        }
      }
    }

    final response = await _dio.get(url, queryParameters: params);

    if (response.statusCode == 200) {
      final data = response.data;
      if (data['ret'] == 0) {
        return _parseTorrentSearchResult(data['data']);
      } else {
        throw Exception('搜索失败: ${data['msg']}');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.data}');
    }
  }

  TorrentSearchResult _parseTorrentSearchResult(Map<String, dynamic> data) {
    final meta = data['meta'] as Map<String, dynamic>;
    final items = (data['data'] as List)
        .map((item) => _parseTorrentItem(item as Map<String, dynamic>))
        .toList();

    return TorrentSearchResult(
      pageNumber: meta['current_page'] as int,
      pageSize: meta['per_page'] as int,
      total: meta['total'] as int,
      totalPages: meta['last_page'] as int,
      items: items,
    );
  }

  TorrentItem _parseTorrentItem(Map<String, dynamic> item) {
    // 解析促销信息
    String discountText = 'Normal';
    final promotionInfo = item['promotion_info'] as Map<String, dynamic>?;
    if (promotionInfo != null) {
      final originalText = promotionInfo['text'] as String? ?? 'Normal';
      // 映射促销信息以兼容现有的显示逻辑
      if (originalText.toLowerCase().contains('2x') &&
          originalText.toLowerCase().contains('free')) {
        discountText = 'Free*2';
      } else {
        discountText = originalText;
      }
    }

    return TorrentItem(
      id: (item['id'] as int).toString(),
      name: item['name'] as String,
      smallDescr: item['small_descr'] as String? ?? '',
      discount: _parseDiscountType(discountText),
      discountEndTime: null, // 暂时没有
      downloadUrl: item['download_url'] as String?,
      seeders: item['seeders'] as int,
      leechers: item['leechers'] as int,
      sizeBytes: item['size'] as int,
      downloadStatus: DownloadStatus.none, // 不支持
      collection: item['has_bookmarked'] as bool? ?? false, 
      imageList: const [], // 暂时没有图片列表
      cover: item['cover'] as String? ?? '',
      createdDate: item['added'] != null ? item['added'] + ':00' : '',
    );
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    try {
      final response = await _dio.get(
        '/api/v1/detail/$id',
        queryParameters: {'includes': 'extra'},
      );

      final data = response.data;
      if (data == null ||
          data['data'] == null ||
          data['data']['data'] == null) {
        throw Exception('响应数据格式错误');
      }

      final torrentData = data['data']['data'];
      final extra = torrentData['extra'] as Map<String, dynamic>?;
      final descr = extra?['descr']?.toString() ?? '';

      return TorrentDetail(descr: descr);
    } catch (e) {
      throw Exception('获取种子详情失败: $e');
    }
  }

  //实际上调用不到了
  @override
  Future<String> genDlToken({required String id, String? url}) async {
    // 检查必要的配置参数
    if (_siteConfig.passKey == null || _siteConfig.passKey!.isEmpty) {
      throw Exception('站点配置缺少passKey，无法生成下载链接');
    }
    if (_siteConfig.userId == null || _siteConfig.userId!.isEmpty) {
      throw Exception('站点配置缺少userId，无法生成下载链接');
    }

    // https://www.ptskit.org/download.php?downhash={userId}.{jwt}
    final jwt = getDownLoadHash(_siteConfig.passKey!, id, _siteConfig.userId!);
    return '${_siteConfig.baseUrl}download.php?downhash=${_siteConfig.userId!}.$jwt';
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    // TODO: 实现NexusPHP下载历史查询
    // 临时返回空历史
    return {'data': <String, dynamic>{}};
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
    try {
      final String endpoint;
      if (make) {
        // 添加收藏
        endpoint = '/api/v1/bookmarks';
      } else {
        // 取消收藏
        endpoint = '/api/v1/bookmarks/delete';
      }

      // 使用FormData发送请求
      final formData = FormData.fromMap({'torrent_id': torrentId});

      final response = await _dio.post(
        endpoint,
        data: formData,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // 检查API返回的结果
        if (data != null && data['ret'] != null && data['ret'] != 0) {
          throw Exception('收藏操作失败: ${data['msg'] ?? '未知错误'}');
        }
        // 成功，无需额外处理
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('收藏操作失败: $e');
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      // TODO: 实现NexusPHP连接测试
      // 临时返回true
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 生成下载哈希值
  ///
  /// 参数:
  /// - [passkey] 用户的passkey
  /// - [id] 种子ID
  /// - [userid] 用户ID
  ///
  /// 返回: JWT编码的下载令牌
  String getDownLoadHash(String passkey, String id, String userid) {
    // 生成MD5密钥: md5(passkey + 当前日期(Ymd) + userid)
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final keyString = passkey + dateStr + userid;
    final keyBytes = utf8.encode(keyString);
    final digest = md5.convert(keyBytes);
    final key = digest.toString();

    // 创建JWT payload
    final payload = {
      'id': id,
      'exp':
          (DateTime.now().millisecondsSinceEpoch / 1000).floor() +
          3600, // 1小时后过期
    };

    // 使用HS256算法生成JWT
    final jwt = JWT(payload);
    final token = jwt.sign(SecretKey(key), algorithm: JWTAlgorithm.HS256);

    return token;
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 通过baseUrl匹配预设配置
    final defaultCategories =
        await SiteConfigService.getDefaultSearchCategories(
          _siteConfig.baseUrl,
        );

    // 如果获取到默认分类配置，则直接返回
    if (defaultCategories.isNotEmpty) {
      return defaultCategories;
    }
    final List<SearchCategoryConfig> categories = [];
    // 默认塞个综合进来
    categories.add(
      SearchCategoryConfig(id: 'all', displayName: '综合', parameters: '{}'),
    );
    try {
      final response = await _dio.get('/api/v1/sections');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['ret'] == 0 && data['data'] != null) {
          // 双循环遍历sections和categories
          final sectionsData = data['data']['data'] as List;
          var onlyOne = false;
          if (sectionsData.length == 1) {
            onlyOne = true;
          }
          for (final section in sectionsData) {
            final sectionName = section['name'] as String;
            final sectionDisplayName = (section['display_name'] as String)
                .replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');
            final categoriesData = section['categories'] as List;

            for (final category in categoriesData) {
              final categoryId = category['id'];
              final categoryName = (category['name'] as String).replaceAll(
                RegExp(r'[\s\u200B-\u200D\uFEFF]'),
                '',
              );
              categories.add(
                SearchCategoryConfig(
                  id: '${sectionName}_$categoryId',
                  displayName: onlyOne
                      ? categoryName
                      : '$sectionDisplayName.$categoryName',
                  parameters: '{"category":"$sectionName#$categoryId"}',
                ),
              );
            }
          }

          return categories;
        }
      }

      // 如果获取失败，返回空列表
      return categories;
    } catch (e) {
      // 发生异常时，返回空列表
      return categories;
    }
  }
}
