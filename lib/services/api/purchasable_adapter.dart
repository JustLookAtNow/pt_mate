import '../../models/purchase_models.dart';

/// 支持应用内购买（魔力值购买付费种子）的站点能力接口
///
/// 只有实现了 PeerGo 购买 API 的站点适配器需要实现本接口，
/// 其余站点适配器无需关心购买逻辑。
abstract class PurchasableAdapter {
  /// 查询指定种子的购买状态（含价格、税费、我的魔力值余额）
  Future<PurchaseStatus> fetchPurchaseStatus(String torrentId);

  /// 购买指定种子
  ///
  /// [expectedPrice] 为该客户端确认过的价格；服务端在价格变化时返回冲突错误，
  /// 不会按新价格静默扣款。[expectedPrice] 为 null 时不提交该字段。
  Future<PurchaseResult> purchaseTorrent(
    String torrentId, {
    int? expectedPrice,
  });

  /// 查询当前用户的有效购买记录
  Future<PurchaseHistoryPage> fetchPurchaseHistory({
    int pageNumber = 1,
    int pageSize = 20,
  });
}
