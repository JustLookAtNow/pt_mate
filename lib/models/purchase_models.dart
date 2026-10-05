/// PeerGo 购买相关数据模型
///
/// 对应 API v1 的「查看购买状态」「购买种子」「获取我的购买记录」三个端点。
/// 所有解析都对字段类型保持宽容（数字可能是 int/double/string），
/// 避免服务端字段类型微调导致客户端崩溃。
library;

/// 购买状态（对应响应中的 `state`）
enum PurchaseState {
  free('free', '免费种子'),
  uploader('uploader', '我是上传者'),
  purchased('purchased', '已购买'),
  purchaseRequired('purchase_required', '需要购买'),
  purchaseDisabled('purchase_disabled', '购买已关闭'),
  unknown('unknown', '未知状态');

  const PurchaseState(this.id, this.label);

  final String id;
  final String label;

  /// 是否已具备访问/下载资格（无需再次购买）
  bool get hasAccess =>
      this == PurchaseState.free ||
      this == PurchaseState.uploader ||
      this == PurchaseState.purchased;

  static PurchaseState fromId(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    for (final state in PurchaseState.values) {
      if (state.id == value) return state;
    }
    return PurchaseState.unknown;
  }
}

/// 购买状态查询结果
class PurchaseStatus {
  final int torrentId;
  final String title;
  final int price;
  final int tax;
  final int sellerIncome;
  final int magicBalance;
  final PurchaseState state;
  final bool isPurchased;
  final DateTime? purchasedAt;
  final bool legacyImport;

  const PurchaseStatus({
    required this.torrentId,
    this.title = '',
    this.price = 0,
    this.tax = 0,
    this.sellerIncome = 0,
    this.magicBalance = 0,
    this.state = PurchaseState.unknown,
    this.isPurchased = false,
    this.purchasedAt,
    this.legacyImport = false,
  });

  /// 是否需要在客户端购买
  bool get requiresPurchase => state == PurchaseState.purchaseRequired;

  /// 是否已具备下载资格（免费种子、上传者或已购买）
  bool get hasAccess => state.hasAccess;

  /// 余额是否足够支付价格与税费
  bool get hasEnoughBalance => magicBalance >= price;

  factory PurchaseStatus.fromJson(Map<String, dynamic> json) => PurchaseStatus(
    torrentId: _asInt(json['torrent_id']),
    title: json['title']?.toString() ?? '',
    price: _asInt(json['price']),
    tax: _asInt(json['tax']),
    sellerIncome: _asInt(json['seller_income']),
    magicBalance: _asInt(json['magic_balance']),
    state: PurchaseState.fromId(json['state']),
    isPurchased: _asBool(json['is_purchased']),
    purchasedAt: _asDateTime(json['purchased_at']),
    legacyImport: _asBool(json['legacy_import']),
  );
}

/// 购买成功结果
class PurchaseResult {
  final String requestId;
  final int torrentId;
  final int price;
  final int tax;
  final int sellerIncome;
  final int balanceAfter;
  final DateTime? purchasedAt;

  /// 是否为幂等重放（同一次请求被重复提交）
  final bool replayed;

  const PurchaseResult({
    this.requestId = '',
    this.torrentId = 0,
    this.price = 0,
    this.tax = 0,
    this.sellerIncome = 0,
    this.balanceAfter = 0,
    this.purchasedAt,
    this.replayed = false,
  });

  factory PurchaseResult.fromJson(Map<String, dynamic> json) => PurchaseResult(
    requestId: json['request_id']?.toString() ?? '',
    torrentId: _asInt(json['torrent_id']),
    price: _asInt(json['price']),
    tax: _asInt(json['tax']),
    sellerIncome: _asInt(json['seller_income']),
    balanceAfter: _asInt(json['balance_after']),
    purchasedAt: _asDateTime(json['purchased_at']),
    replayed: _asBool(json['replayed']),
  );
}

/// 单条购买记录
class PurchaseRecord {
  final int torrentId;
  final String title;
  final String categoryName;
  final String torrentState;
  final int price;
  final DateTime? purchasedAt;
  final bool legacyImport;

  const PurchaseRecord({
    required this.torrentId,
    this.title = '',
    this.categoryName = '',
    this.torrentState = '',
    this.price = 0,
    this.purchasedAt,
    this.legacyImport = false,
  });

  factory PurchaseRecord.fromJson(Map<String, dynamic> json) => PurchaseRecord(
    torrentId: _asInt(json['torrent_id']),
    title: json['title']?.toString() ?? '',
    categoryName: json['category_name']?.toString() ?? '',
    torrentState: json['torrent_state']?.toString() ?? '',
    price: _asInt(json['price']),
    purchasedAt: _asDateTime(json['purchased_at']),
    legacyImport: _asBool(json['legacy_import']),
  );
}

/// 购买记录分页结果
class PurchaseHistoryPage {
  final List<PurchaseRecord> records;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  const PurchaseHistoryPage({
    this.records = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.totalPages = 0,
  });

  bool get isEmpty => records.isEmpty;

  factory PurchaseHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['purchases'] as List? ?? const [];
    return PurchaseHistoryPage(
      records: rawList
          .whereType<Map>()
          .map((e) => PurchaseRecord.fromJson(e.cast<String, dynamic>()))
          .toList(),
      total: _asInt(json['total']),
      page: json['page'] == null ? 1 : _asInt(json['page']),
      pageSize: json['page_size'] == null ? 20 : _asInt(json['page_size']),
      totalPages: _asInt(json['total_pages']),
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.round() ?? fallback;
  }
  return fallback;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

DateTime? _asDateTime(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw == 'null') return null;
  try {
    var normalized = raw;
    if (normalized.length >= 19 && normalized[10] == ' ') {
      normalized = normalized.replaceRange(10, 11, 'T');
    }
    if (normalized.contains(RegExp(r'Z|[+-]\d{2}:?\d{2}$'))) {
      return DateTime.parse(normalized).toLocal();
    }
    return DateTime.parse('$normalized+08:00').toLocal();
  } catch (_) {
    return null;
  }
}
