import '../../models/app_models.dart';
import 'api_client.dart';
import 'mteam_adapter.dart';
import 'nexusphp_adapter.dart';

/// 统一的站点协议接口
/// 定义所有站点适配器都应该实现的基本操作
abstract class SiteAdapter {
  /// 站点配置
  SiteConfig get siteConfig;
  
  /// 初始化适配器
  Future<void> init(SiteConfig config);
  
  /// 获取用户资料
  Future<MemberProfile> fetchMemberProfile({String? apiKey});
  
  /// 搜索种子
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  });
  
  /// 获取种子详情
  Future<TorrentDetail> fetchTorrentDetail(String id);
  
  /// 生成下载令牌并返回下载URL
  Future<String> genDlToken({required String id});
  
  /// 查询下载历史
  Future<Map<String, dynamic>> queryHistory({required List<String> tids});
  
  /// 切换种子收藏状态
  Future<void> toggleCollection({required String id, required bool make});
  
  /// 测试连接是否有效
  Future<bool> testConnection();
}

/// 站点适配器工厂
class SiteAdapterFactory {
  static SiteAdapter createAdapter(SiteConfig config) {
    switch (config.siteType) {
      case SiteType.mteam:
        return MTeamAdapter();
      case SiteType.nexusphp:
        return NexusPHPAdapter();
    }
  }
}