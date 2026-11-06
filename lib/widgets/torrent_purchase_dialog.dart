import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/purchase_models.dart';
import '../services/api/api_exceptions.dart';
import '../services/api/api_service.dart';
import '../utils/notification_helper.dart';
import '../utils/url_launcher_helper.dart';

/// 购买状态加载器，默认走 [ApiService]；测试可注入替身
typedef PurchaseStatusLoader = Future<PurchaseStatus> Function(
  String torrentId,
);

/// 购买提交器，默认走 [ApiService]；测试可注入替身
typedef PurchaseSubmitter = Future<PurchaseResult> Function(
  String torrentId,
  int? expectedPrice,
);

/// 购买弹窗的返回结果
class TorrentPurchaseOutcome {
  /// 是否可以继续下载（已购买、免费、上传者或刚刚购买成功）
  final bool canProceed;

  /// 购买成功时的服务端结果
  final PurchaseResult? purchase;

  const TorrentPurchaseOutcome({required this.canProceed, this.purchase});
}

/// 付费种子购买弹窗
///
/// 仅在用户明确点击确认时发起扣款，并在提交时携带 `expected_price`，
/// 服务端价格变化会返回冲突错误并要求用户重新确认。
class TorrentPurchaseDialog extends StatefulWidget {
  const TorrentPurchaseDialog({
    super.key,
    required this.torrentId,
    this.torrentTitle,
    this.siteConfig,
    this.loadStatus,
    this.submitPurchase,
  });

  final String torrentId;
  final String? torrentTitle;
  final SiteConfig? siteConfig;
  final PurchaseStatusLoader? loadStatus;
  final PurchaseSubmitter? submitPurchase;

  @override
  State<TorrentPurchaseDialog> createState() => _TorrentPurchaseDialogState();
}

class _TorrentPurchaseDialogState extends State<TorrentPurchaseDialog> {
  PurchaseStatus? _status;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<PurchaseStatus> _requestStatus() {
    final loader = widget.loadStatus;
    if (loader != null) return loader(widget.torrentId);
    return ApiService.instance.fetchPurchaseStatus(
      widget.torrentId,
      siteConfig: widget.siteConfig,
    );
  }

  Future<PurchaseResult> _requestPurchase(int expectedPrice) {
    final submitter = widget.submitPurchase;
    if (submitter != null) return submitter(widget.torrentId, expectedPrice);
    return ApiService.instance.purchaseTorrent(
      widget.torrentId,
      expectedPrice: expectedPrice,
      siteConfig: widget.siteConfig,
    );
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _requestStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e, fallback: '获取购买状态失败');
        _loading = false;
      });
    }
  }

  Future<void> _confirmPurchase() async {
    final status = _status;
    if (status == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _requestPurchase(status.price);
      if (!mounted) return;
      Navigator.of(context)
          .pop(TorrentPurchaseOutcome(canProceed: true, purchase: result));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyError(e, fallback: '购买失败');
      });
      // 价格变化或状态变化后，重新拉取最新状态供用户再次确认
      if (e is SitePurchaseException &&
          (e.reason == PurchaseFailureReason.priceChanged ||
              e.reason == PurchaseFailureReason.notAllowed)) {
        await _loadStatus();
        if (mounted) {
          setState(() => _error = _friendlyError(e, fallback: '购买失败'));
        }
      }
    }
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is SiteException) {
      if (error is SitePurchaseException && error.statusCode == 403) {
        return 'API Key 缺少 torrent:purchase:write 权限，请到站点「账户设置 → API Key」勾选后重试';
      }
      return error.message.isEmpty ? fallback : error.message;
    }
    return '$fallback：$error';
  }

  void _proceedWithoutPurchase() {
    Navigator.of(context).pop(const TorrentPurchaseOutcome(canProceed: true));
  }

  Future<void> _openWebPurchase() async {
    final config = widget.siteConfig;
    var base = config?.baseUrl ?? 'https://rousi.pro/';
    if (!base.endsWith('/')) base = '$base/';
    final url = '${base}torrent/${widget.torrentId}';
    if (!mounted) return;
    await UrlLauncherHelper.launchBrowser(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('购买种子'),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _buildBody(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildBody() {
    final status = _status;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.torrentTitle != null && widget.torrentTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.torrentTitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (status != null) ..._buildStatusRows(status),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildStatusRows(PurchaseStatus status) {
    final rows = <Widget>[];

    if (status.title.isNotEmpty &&
        (widget.torrentTitle == null || widget.torrentTitle!.isEmpty)) {
      rows.add(Text(status.title));
    }

    if (status.requiresPurchase) {
      rows.addAll([
        _buildRow('价格', '${status.price} 魔力值'),
        _buildRow('税费', '${status.tax} 魔力值'),
        _buildRow('上传者收入', '${status.sellerIncome} 魔力值'),
        _buildRow('我的魔力值', '${status.magicBalance}'),
      ]);
      if (!status.hasEnoughBalance) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '魔力值余额不足，无法购买该种子',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
      } else {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '购买后无法退款，请在确认后扣款。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
    } else if (status.hasAccess) {
      final reason = switch (status.state) {
        PurchaseState.purchased => '该种子已购买，可直接下载。',
        PurchaseState.uploader => '你是该种子的上传者，可直接下载。',
        _ => '该种子为免费种子，可直接下载。',
      };
      rows.add(Text(reason));
    } else if (status.state == PurchaseState.purchaseDisabled) {
      rows.add(const Text('该种子当前已关闭购买，请在站点网页端查看。'));
    } else {
      rows.add(const Text('当前状态无法在应用内购买，请在站点网页端确认。'));
    }

    return rows;
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    final status = _status;
    final canConfirm =
        status != null &&
        status.requiresPurchase &&
        status.hasEnoughBalance &&
        !_submitting;

    return [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 1.0,
          ),
        ),
        child: const Text('取消'),
      ),
      // 只有拿不到购买状态时才退化为网页端购买；购买失败仍保留重试入口
      if (status == null)
        TextButton(onPressed: _openWebPurchase, child: const Text('前往网页端购买'))
      else if (status.hasAccess)
        ElevatedButton(
          onPressed: _proceedWithoutPurchase,
          child: const Text('继续'),
        )
      else if (status.requiresPurchase)
        ElevatedButton(
          onPressed: canConfirm ? _confirmPurchase : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('确认购买（花费 ${status.price} 魔力值）'),
        )
      else
        TextButton(onPressed: _openWebPurchase, child: const Text('前往网页端购买')),
    ];
  }
}

/// 获取下载链接；遇到付费未购买的种子时弹出购买确认框
///
/// 返回 `null` 表示用户取消或购买失败，调用方应静默终止本次下载。
Future<String?> resolveDownloadUrlWithPurchase({
  required BuildContext context,
  required String torrentId,
  String? url,
  String? torrentTitle,
  SiteConfig? siteConfig,
}) async {
  Future<String> fetchUrl() => ApiService.instance.genDlToken(
    id: torrentId,
    url: url,
    siteConfig: siteConfig,
  );

  try {
    return await fetchUrl();
  } on SitePurchaseRequiredException {
    // 继续走购买流程
  }

  // 最多允许两轮购买确认，避免服务端状态异常时反复扣款
  for (var attempt = 0; attempt < 2; attempt++) {
    if (!context.mounted) return null;

    final outcome = await showDialog<TorrentPurchaseOutcome>(
      context: context,
      builder: (_) => TorrentPurchaseDialog(
        torrentId: torrentId,
        torrentTitle: torrentTitle,
        siteConfig: siteConfig,
      ),
    );

    if (outcome == null || !outcome.canProceed) return null;

    final purchase = outcome.purchase;
    if (purchase != null && context.mounted) {
      NotificationHelper.showInfo(
        context,
        '购买成功，已扣除 ${purchase.price} 魔力值，余额 ${purchase.balanceAfter}',
      );
    }

    try {
      return await fetchUrl();
    } on SitePurchaseRequiredException {
      // 购买后仍拿不到下载链接，继续下一轮确认（或退出）
    }
  }

  if (context.mounted) {
    NotificationHelper.showError(context, '购买后仍无法获取下载链接，请在站点网页端确认账号状态');
  }
  return null;
}
