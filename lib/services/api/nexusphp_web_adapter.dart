import '../../models/app_models.dart';
import 'api_client.dart';
import 'site_adapter.dart';
import '../site_config_service.dart';
import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';

/// NexusPHP Web站点适配器
/// 用于处理基于Web接口的NexusPHP站点
class NexusPHPWebAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;
    _dio = Dio();
    _dio.options.baseUrl = _siteConfig.baseUrl;
    _dio.options.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    _dio.options.responseType = ResponseType.plain; // 设置为plain避免JSON解析警告
    
    // 设置Cookie
    if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
      _dio.options.headers['Cookie'] = _siteConfig.cookie;
    }
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final response = await _dio.get('/usercp.php');
      final soup = BeautifulSoup(response.data);
      
      // 查找用户信息块
      final infoBlock = soup.find('table', id: 'info_block');
      if (infoBlock == null) {
        throw Exception('未找到用户信息块');
      }
      
      final userInfo = infoBlock.find('span', class_: 'medium');
      if (userInfo == null) {
        throw Exception('未找到用户信息');
      }
      
      // 提取用户名
      final usernameElement = userInfo.find('span')?.a?.b;
      if (usernameElement == null) {
        throw Exception('未找到用户名');
      }
      final username = usernameElement.text.trim();
      
      // 提取文本信息
      final textInfo = userInfo.text.trim();
      
      // 使用正则表达式提取各项数据
      final ratioMatch = RegExp(r'分享率:\s*([^\s]+)').firstMatch(textInfo);
      final ratio = ratioMatch?.group(1)?.trim() ?? '0';
      
      final uploadMatch = RegExp(r'上传量:\s*([^\s]+)').firstMatch(textInfo);
      final uploadString = uploadMatch?.group(1)?.trim() ?? '0 B';
      
      final downloadMatch = RegExp(r'下载量:\s*([^\s]+)').firstMatch(textInfo);
      final downloadString = downloadMatch?.group(1)?.trim() ?? '0 B';
      
      final bonusMatch = RegExp(r':\s*([^\s]+)\s*\[签到').firstMatch(textInfo);
      final bonus = bonusMatch?.group(1)?.trim() ?? '0';
      
      // 将字符串格式的数据转换为数字（简单转换，实际可能需要更复杂的逻辑）
      double shareRate = double.tryParse(ratio) ?? 0.0;
      double bonusPoints = double.tryParse(bonus) ?? 0.0;
      
      // 对于bytes，由于web版本直接提供格式化字符串，这里设置为0
      // 实际使用时应该使用uploadedBytesString和downloadedBytesString
      int uploadedBytes = 0;
      int downloadedBytes = 0;
      
      return MemberProfile(
        username: username,
        bonus: bonusPoints,
        shareRate: shareRate,
        uploadedBytes: uploadedBytes,
        downloadedBytes: downloadedBytes,
        uploadedBytesString: uploadString,
        downloadedBytesString: downloadString,
        userId: null, // Web版本暂时不提供用户ID
      );
    } catch (e) {
      throw Exception('获取用户资料失败: $e');
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
    // TODO: 实现搜索种子
    throw UnimplementedError('searchTorrents not implemented');
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    // TODO: 实现获取种子详情
    throw UnimplementedError('fetchTorrentDetail not implemented');
  }

  @override
  Future<String> genDlToken({required String id}) async {
    // TODO: 实现生成下载令牌
    throw UnimplementedError('genDlToken not implemented');
  }

  @override
  Future<Map<String, dynamic>> queryHistory({required List<String> tids}) async {
    // TODO: 实现查询下载历史
    throw UnimplementedError('queryHistory not implemented');
  }

  @override
  Future<void> toggleCollection({required String id, required bool make}) async {
    // TODO: 实现切换种子收藏状态
    throw UnimplementedError('toggleCollection not implemented');
  }

  @override
  Future<bool> testConnection() async {
    // TODO: 实现测试连接
    throw UnimplementedError('testConnection not implemented');
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 优先匹配baseUrl，然后类型
    final defaultCategories =
        await SiteConfigService.getDefaultSearchCategories(
          _siteConfig.siteType.id,
          baseUrl: _siteConfig.baseUrl,
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
      final response = await _dio.get('/usercp.php?action=tracker');

      if (response.statusCode == 200) {
         final htmlContent = response.data as String;
         final soup = BeautifulSoup(htmlContent);
         
         // 解析HTML获取分类信息
         final parsedCategories = _parseCategories(soup);
         categories.addAll(parsedCategories);
       }

      return categories;
    } catch (e) {
      // 发生异常时，返回默认分类
      return categories;
    }
  }

  /// 解析HTML文档中的分类信息
  List<SearchCategoryConfig> _parseCategories(BeautifulSoup soup) {
    final List<SearchCategoryConfig> categories = [];
    
    final outerElement = soup.find('#outer');
    if (outerElement == null) return categories;
    
    final tables = outerElement.findAll('table');
    if (tables.length < 2) return categories;
    
    final table2 = tables[1]; // 第2个table（索引1）
    final infoTables = table2.findAll('table');
    
    int batchIndex = 1;
    var currentBatch = <Map<String, String>>[];
    
    for (final infoTable in infoTables) {
      final rows = infoTable.findAll('tr');
      
      for (final row in rows) {
        final tds = row.findAll('td');
        var hasCategories = false;
        
        if (tds.isNotEmpty) {
          for (final td in tds) {
            final img = td.find('img');
            final checkbox = td.find('input[type="checkbox"]');
            
            if (img != null) {
              final alt = img.attributes['alt'] ?? '';
              final title = img.attributes['title'] ?? '';
              final categoryName = alt.isNotEmpty ? alt : title;
              final categoryId = checkbox?.attributes['id'] ?? '';
              
              if (categoryName.isNotEmpty && categoryId.isNotEmpty) {
                currentBatch.add({
                  'name': categoryName,
                  'id': categoryId,
                });
                hasCategories = true;
              }
            }
          }
        }
        
        // 如果当前行没有分类信息，处理当前批次（如果有内容）
        if (!hasCategories && currentBatch.isNotEmpty) {
          _processBatch(categories, currentBatch, batchIndex);
          batchIndex++;
          currentBatch.clear();
        }
      }
    }
    
    // 处理最后一个批次（如果还有未处理的分类）
    if (currentBatch.isNotEmpty) {
      _processBatch(categories, currentBatch, batchIndex);
    }
    
    return categories;
  }
  
  /// 处理分类批次，添加到分类列表中
  void _processBatch(List<SearchCategoryConfig> categories, 
                     List<Map<String, String>> batch, int batchIndex) {
    String prefix;
    if (batchIndex == 1) {
      prefix = 'normal#';
    } else if (batchIndex == 2) {
      prefix = 'special#';
    } else {
      prefix = 'batch$batchIndex#';
    }
    
    for (final category in batch) {
      final categoryName = category['name']!;
      final categoryId = category['id']!;
      
      categories.add(
        SearchCategoryConfig(
          id: categoryId,
          displayName: batchIndex > 1 ? 's_$categoryName' : categoryName,
          parameters: '{"category":"$prefix$categoryId"}',
        ),
      );
    }
  }
}