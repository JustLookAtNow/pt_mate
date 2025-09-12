import '../../models/app_models.dart';
import '../storage/storage_service.dart';
import 'site_adapter.dart';

/// 统一的API服务管理器
/// 负责管理不同站点的适配器实例
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  
  final Map<String, SiteAdapter> _adapters = {};
  SiteAdapter? _activeAdapter;
  
  /// 初始化服务，加载活跃站点的适配器
  Future<void> init() async {
    final activeSite = await StorageService.instance.getActiveSiteConfig();
    if (activeSite != null) {
      await _initAdapter(activeSite);
    }
  }
  
  /// 获取当前活跃的适配器
  SiteAdapter? get activeAdapter => _activeAdapter;
  
  /// 获取指定站点的适配器
  Future<SiteAdapter> getAdapter(SiteConfig siteConfig) async {
    final adapterId = siteConfig.id;
    
    if (_adapters.containsKey(adapterId)) {
      return _adapters[adapterId]!;
    }
    
    // 创建新的适配器实例
    final adapter = SiteAdapterFactory.createAdapter(siteConfig);
    await adapter.init(siteConfig);
    _adapters[adapterId] = adapter;
    
    return adapter;
  }
  
  /// 设置活跃站点
  Future<void> setActiveSite(SiteConfig siteConfig) async {
    // 清除该站点的缓存适配器，确保使用最新配置
    removeAdapter(siteConfig.id);
    _activeAdapter = await getAdapter(siteConfig);
  }
  
  /// 移除站点适配器
  void removeAdapter(String siteId) {
    _adapters.remove(siteId);
    if (_activeAdapter?.siteConfig.id == siteId) {
      _activeAdapter = null;
    }
  }
  
  /// 清除所有适配器
  void clearAdapters() {
    _adapters.clear();
    _activeAdapter = null;
  }
  
  /// 私有方法：初始化指定站点的适配器
  Future<void> _initAdapter(SiteConfig siteConfig) async {
    try {
      _activeAdapter = await getAdapter(siteConfig);
    } catch (e) {
      // 初始化失败，记录错误但不抛出异常
      // Failed to initialize adapter for site ${siteConfig.name}: $e
    }
  }
  
  // 便捷方法：直接使用活跃适配器进行操作
  
  /// 获取用户资料
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.fetchMemberProfile(apiKey: apiKey);
  }
  
  /// 搜索种子
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.searchTorrents(
      keyword: keyword,
      pageNumber: pageNumber,
      pageSize: pageSize,
      onlyFav: onlyFav,
      additionalParams: additionalParams,
    );
  }
  
  /// 获取种子详情
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.fetchTorrentDetail(id);
  }
  
  /// 生成下载令牌
  Future<String> genDlToken({required String id,String? url}) async {
    if (url != null && url.isNotEmpty) {
      return url;
    }
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.genDlToken(id: id);
  }
  
  /// 查询下载历史
  Future<Map<String, dynamic>> queryHistory({required List<String> tids}) async {
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.queryHistory(tids: tids);
  }
  
  /// 切换种子收藏状态
  Future<void> toggleCollection({required String id, required bool make}) async {
    if (_activeAdapter == null) {
      throw StateError('No active site adapter available');
    }
    return _activeAdapter!.toggleCollection(id: id, make: make);
  }
  
  /// 测试连接
  Future<bool> testConnection() async {
    if (_activeAdapter == null) {
      return false;
    }
    return _activeAdapter!.testConnection();
  }
  
  /// 使用指定站点配置测试连接
  Future<bool> testConnectionWithSite(SiteConfig siteConfig) async {
    try {
      final adapter = await getAdapter(siteConfig);
      return adapter.testConnection();
    } catch (e) {
      return false;
    }
  }
}