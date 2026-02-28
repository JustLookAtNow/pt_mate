import '../../models/app_models.dart';
import 'mteam_adapter.dart';
import 'nexusphp_adapter.dart';
import 'nexusphp_web_adapter.dart';
import 'rousi_adapter.dart';
import 'gazelle_adapter.dart';

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

  /// 获取种子评论列表
  Future<TorrentCommentList> fetchComments(String id, {int pageNumber = 1, int pageSize = 20});

  /// 生成下载令牌并返回下载URL
  Future<String> genDlToken({required String id, String? url});

  /// 查询下载历史
  Future<Map<String, dynamic>> queryHistory({required List<String> tids});

  /// 切换种子收藏状态
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  });

  /// 测试连接是否有效
  Future<bool> testConnection();

  /// 获取站点的分类条件配置
  Future<List<SearchCategoryConfig>> getSearchCategories();
}

/// 站点适配器工厂
class SiteAdapterFactory {
  static SiteAdapter createAdapter(SiteConfig config) {
    switch (config.siteType) {
      case SiteType.mteam:
        return MTeamAdapter();
      case SiteType.nexusphp:
        return NexusPHPAdapter();
      case SiteType.nexusphpweb:
        return NexusPHPWebAdapter();
      case SiteType.rousi:
        return RousiAdapter();
      case SiteType.gazelle:
        return GazelleAdapter();
    }
  }
}