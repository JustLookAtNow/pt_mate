import '../utils/screen_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import 'dart:math' as math;

import '../utils/format.dart';
import 'cached_network_image.dart';

// Helper method to parse rating
// Using a static final RegExp to avoid recompiling the pattern on every call, improving performance.
final RegExp _ratingRegExp = RegExp(r'([0-9]+(?:\.[0-9]+)?)');

bool _hasRatingValue(String? r) {
  if (r == null) return false;
  final t = r.trim();
  if (t.isEmpty || t == 'N/A') return false;
  final m = _ratingRegExp.firstMatch(t);
  if (m == null) return false;
  final v = double.tryParse(m.group(1)!);
  return v != null && v > 0;
}

/// 种子列表项组件
///
/// 可复用的种子列表项组件，支持：
/// - 基本种子信息显示（名称、描述、大小、做种/下载数等）
/// - 优惠标签显示
/// - 收藏和下载功能按钮
/// - 选择模式支持
/// - 聚合搜索模式下的站点名称显示
class TorrentListItem extends StatelessWidget {
  /// 种子数据
  final TorrentItem torrent;

  /// 是否被选中
  final bool isSelected;

  /// 是否处于选择模式
  final bool isSelectionMode;

  /// 当前站点配置（用于判断功能支持）
  final SiteConfig? currentSite;

  /// 是否为聚合搜索模式
  final bool isAggregateMode;

  /// 聚合搜索模式下的站点名称
  final String? siteName;
  final bool? suspendImageLoading;

  /// 用户全局设置的封面显示偏好（true=自动，false=不显示）
  final bool? showCoverSetting;

  /// 点击事件回调
  final VoidCallback? onTap;

  /// 长按事件回调
  final VoidCallback? onLongPress;

  /// 收藏切换回调
  final VoidCallback? onToggleCollection;

  /// 下载回调
  final VoidCallback? onDownload;
  final BatchOperationType? batchOperationType;
  final BatchItemState batchItemState;
  final String? batchErrorMessage;
  final VoidCallback? onRetryBatchAction;

  const TorrentListItem({
    super.key,
    required this.torrent,
    required this.isSelected,
    required this.isSelectionMode,
    this.currentSite,
    this.isAggregateMode = false,
    this.siteName,
    this.onTap,
    this.onLongPress,
    this.onToggleCollection,
    this.onDownload,
    this.suspendImageLoading,
    this.showCoverSetting,
    this.batchOperationType,
    this.batchItemState = BatchItemState.idle,
    this.batchErrorMessage,
    this.onRetryBatchAction,
  });

  @override
  Widget build(BuildContext context) {
    // 检测是否为移动设备（屏幕宽度小于600px）
    final isMobile = !ScreenUtils.isLargeScreen(context);
    // 将站点配置的 showCover 与用户全局设置做与运算
    final siteShowCover = currentSite?.features.showCover ?? true;
    final showCover = siteShowCover && (showCoverSetting ?? true);

    final hasDouban = _hasRatingValue(torrent.doubanRating);
    final hasImdb = _hasRatingValue(torrent.imdbRating);
    final hasAnyRating = hasDouban || hasImdb;
    final double rightMinHeight = showCover
        ? (isMobile && hasAnyRating ? 130.0 : 100.0)
        : 70.0;

    // 构建主要内容
    Widget mainContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主体卡片内容
          Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6)
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // 移动端已收藏大红心背景
                  if (isMobile && torrent.collection)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Icon(
                        Icons.favorite,
                        color: Colors.red.withValues(alpha: 0.7),
                        size: 30,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 封面截图和创建时间（在 showCover 为 true 时显示）
                          if (showCover && (suspendImageLoading != true))
                            TorrentCover(
                              torrent: torrent,
                              currentSite: currentSite,
                              isMobile: isMobile,
                              hasDouban: hasDouban,
                              hasImdb: hasImdb,
                            ),

                          Expanded(
                            child: TorrentInfo(
                              torrent: torrent,
                              currentSite: currentSite,
                              isAggregateMode: isAggregateMode,
                              siteName: siteName,
                              isMobile: isMobile,
                              showCover: showCover,
                              hasDouban: hasDouban,
                              hasImdb: hasImdb,
                              hasAnyRating: hasAnyRating,
                              rightMinHeight: rightMinHeight,
                              batchOperationType: batchOperationType,
                              batchItemState: batchItemState,
                              batchErrorMessage: batchErrorMessage,
                              onRetryBatchAction: onRetryBatchAction,
                            ),
                          ),
                          // 桌面端显示操作按钮
                          if (!isMobile) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Container(
                                width: 1,
                                height: math.max(60, rightMinHeight - 16),
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              height: math.max(60, rightMinHeight - 8),
                              child: TorrentActions(
                                torrent: torrent,
                                currentSite: currentSite,
                                onToggleCollection: onToggleCollection,
                                onDownload: onDownload,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isAggregateMode && siteName != null)
            Positioned(
              top: 0,
              right: 0,
              child: _AggregateSiteChip(siteName: siteName!),
            ),
        ],
      ),
    );

    // 移动设备使用自定义左滑功能
    if (isMobile) {
      return _SwipeableItem(
        onTap: onTap,
        onLongPress: onLongPress,
        actionBuilder: (context, close) => _buildSwipeActions(context, close),
        isAggregateMode: isAggregateMode,
        child: mainContent,
      );
    } else {
      // 桌面端直接返回带手势检测的内容（附加右键长按等效功能）
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: mainContent,
      );
    }
  }

  // 构建左滑动作按钮
  List<Widget> _buildSwipeActions(BuildContext context, VoidCallback close) {
    List<Widget> actions = [];
    final favoriteDisabled = onToggleCollection == null;
    final downloadDisabled = onDownload == null;

    // 添加收藏按钮（如果支持）
    if (currentSite?.features.supportCollection ?? true) {
      actions.add(
        Container(
          width: 60,
          margin: const EdgeInsets.only(left: 4),
          child: Material(
            color: favoriteDisabled
                ? Theme.of(context).disabledColor.withValues(alpha: 0.6)
                : torrent.collection
                ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.red.shade800
                      : Colors.red)
                : (Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.7)
                      : Theme.of(context).colorScheme.secondary),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: favoriteDisabled
                  ? null
                  : () {
                      close();
                      if (onToggleCollection != null) onToggleCollection!();
                    },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    torrent.collection ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    torrent.collection ? '取消' : '收藏',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 添加下载按钮（如果支持）
    if (currentSite?.features.supportDownload ?? true) {
      actions.add(
        Container(
          width: 60,
          margin: const EdgeInsets.only(left: 4),
          child: Material(
            color: downloadDisabled
                ? Theme.of(context).disabledColor.withValues(alpha: 0.6)
                : Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                : Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: downloadDisabled
                  ? null
                  : () {
                      close();
                      if (onDownload != null) onDownload!();
                    },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_outlined, color: Colors.white, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    '下载',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (onRetryBatchAction != null) {
      actions.add(
        Container(
          width: 60,
          margin: const EdgeInsets.only(left: 4),
          child: Material(
            color: Theme.of(context).colorScheme.error,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                close();
                onRetryBatchAction!();
              },
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(height: 2),
                  Text(
                    '重试',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return actions;
  }
}

class TorrentInfo extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final bool isAggregateMode;
  final String? siteName;
  final bool isMobile;
  final bool showCover;
  final bool hasDouban;
  final bool hasImdb;
  final bool hasAnyRating;
  final double rightMinHeight;
  final BatchOperationType? batchOperationType;
  final BatchItemState batchItemState;
  final String? batchErrorMessage;
  final VoidCallback? onRetryBatchAction;

  const TorrentInfo({
    super.key,
    required this.torrent,
    this.currentSite,
    required this.isAggregateMode,
    this.siteName,
    required this.isMobile,
    required this.showCover,
    required this.hasDouban,
    required this.hasImdb,
    required this.hasAnyRating,
    required this.rightMinHeight,
    this.batchOperationType,
    this.batchItemState = BatchItemState.idle,
    this.batchErrorMessage,
    this.onRetryBatchAction,
  });

  /// 获取优惠类型对应的颜色
  Color _discountColor(DiscountType discount) {
    switch (discount.colorType) {
      case DiscountColorType.green:
        return Colors.green;
      case DiscountColorType.yellow:
        return Colors.amber;
      case DiscountColorType.blue:
        return Colors.lightBlue;
      case DiscountColorType.none:
        return Colors.grey;
    }
  }

  /// 获取优惠类型显示文本
  String _discountText(DiscountType discount, DateTime? endTime) {
    final baseText = discount.displayText;

    if ((discount == DiscountType.free || discount == DiscountType.twoXFree) &&
        endTime != null) {
      final endDateTime = endTime;
      final now = DateTime.now();
      final difference = endDateTime.difference(now);
      final hoursLeft = difference.inHours;

      if (hoursLeft > 0) {
        return '$baseText ${hoursLeft}h';
      }
    }

    return baseText;
  }

  /// 构建下载状态图标
  Widget _buildDownloadStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return const Tooltip(
          message: '已完成',
          child: Icon(Icons.download_done, color: Colors.green, size: 20),
        );
      case DownloadStatus.downloading:
        return const Tooltip(
          message: '下载中',
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
        );
      case DownloadStatus.none:
        return const SizedBox(width: 20); // 占位，保持布局一致
    }
  }

  String _batchActionLabel() {
    switch (batchOperationType) {
      case BatchOperationType.favorite:
        return '收藏';
      case BatchOperationType.download:
        return '下载';
      case null:
        return '操作';
    }
  }

  Widget? _buildBatchStatus(BuildContext context) {
    switch (batchItemState) {
      case BatchItemState.idle:
        return null;
      case BatchItemState.running:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '批量${_batchActionLabel()}中',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case BatchItemState.success:
        final successContainerColor = Theme.of(
          context,
        ).colorScheme.tertiaryContainer;
        final successForegroundColor = Theme.of(
          context,
        ).colorScheme.onTertiaryContainer;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: successContainerColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: successForegroundColor),
              const SizedBox(width: 6),
              Text(
                '批量${_batchActionLabel()}成功',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: successForegroundColor),
              ),
            ],
          ),
        );
      case BatchItemState.failed:
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: batchErrorMessage ?? '批量${_batchActionLabel()}失败',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '批量${_batchActionLabel()}失败',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onRetryBatchAction != null)
              FilledButton.tonalIcon(
                onPressed: onRetryBatchAction,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重试'),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchStatus = _buildBatchStatus(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 中间内容列
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tags, Pin and Site
              if (torrent.isTop || torrent.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _TagsView(
                    tags: torrent.tags,
                    isTop: torrent.isTop,
                  ),
                ),

              Tooltip(
                message: torrent.name,
                child: Text(
                  torrent.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium?.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Subtitle
              Text(
                torrent.smallDescr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              // Date
              Text(
                '发布于 ${Formatters.formatTorrentCreatedDate(torrent.createdDate)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (batchStatus != null) ...[
                const SizedBox(height: 4),
                batchStatus,
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 右侧数据列
        SizedBox(
          width: 55, // Fixed width for right column for alignment
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: isMobile ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
// discount
              if (torrent.discount != DiscountType.normal)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: _discountColor(
                        torrent.discount,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _discountText(torrent.discount, torrent.discountEndTime),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _discountColor(torrent.discount),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // seeders
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_upward, color: Colors.green, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${torrent.seeders}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // leechers
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward, color: Colors.red, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${torrent.leechers}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // size
              Text(
                Formatters.dataFromBytes(torrent.sizeBytes),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              // comments
              if (currentSite?.siteType == SiteType.mteam ||
                  currentSite?.siteType == SiteType.nexusphp)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat,
                      size: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${torrent.comments}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              // history download status
              if (currentSite?.features.supportHistory ?? true)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildDownloadStatusIcon(torrent.downloadStatus),
                ),
            ],
          ),
        ),
        if (isMobile) const SizedBox(width: 8),
      ],
    );
  }
}

class TorrentCover extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final bool isMobile;
  final bool hasDouban;
  final bool hasImdb;

  const TorrentCover({
    super.key,
    required this.torrent,
    this.currentSite,
    required this.isMobile,
    required this.hasDouban,
    required this.hasImdb,
  });

  Widget _buildCoverPlaceholder(
    BuildContext context, {
    required Widget icon,
    required String text,
  }) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 80,
      height: 115,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: color),
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 115,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: GestureDetector(
              onTap: () async {
                if (torrent.cover.isNotEmpty) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  await showDialog(
                    context: context,
                    builder: (ctx) => Dialog(
                      child: CachedNetworkImage(
                        imageUrl: torrent.cover,
                        siteConfig: currentSite,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                  if (context.mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    });
                  }
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: torrent.cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: torrent.cover,
                        siteConfig: currentSite,
                        width: 80,
                        height: 115,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildCoverPlaceholder(
                            context,
                            icon: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            text: '加载中',
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return _buildCoverPlaceholder(
                            context,
                            icon: const Icon(Icons.image_outlined, size: 24),
                            text: '加载失败',
                          );
                        },
                      )
                    : _buildCoverPlaceholder(
                        context,
                        icon: const Icon(Icons.image_outlined, size: 24),
                        text: '暂无',
                      ),
              ),
            ),
          ),
          if (hasDouban || hasImdb)
            Positioned(
              left: 0,
              bottom: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImdb)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5C518),
                        borderRadius: BorderRadius.only(
                          topRight: const Radius.circular(6),
                          bottomLeft: hasDouban ? Radius.zero : const Radius.circular(6),
                        ),
                      ),
                      child: Text(
                        'IMDB ${torrent.imdbRating}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (hasDouban)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF007711),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(6),
                          bottomLeft: Radius.circular(6),
                        ),
                      ),
                      child: Text(
                        '豆 ${torrent.doubanRating}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TorrentActions extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final VoidCallback? onToggleCollection;
  final VoidCallback? onDownload;

  const TorrentActions({
    super.key,
    required this.torrent,
    this.currentSite,
    this.onToggleCollection,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 收藏按钮 - 仅在站点支持收藏功能时显示
        if (currentSite?.features.supportCollection ?? true)
          IconButton(
            onPressed: onToggleCollection,
            icon: Icon(
              torrent.collection ? Icons.favorite : Icons.favorite_border,
              color: torrent.collection ? Colors.red : null,
            ),
            tooltip: torrent.collection ? '取消收藏' : '收藏',
            padding: EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        // 下载按钮 - 仅在站点支持下载功能时显示
        if (currentSite?.features.supportDownload ?? true)
          IconButton(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载',
            padding: EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
      ],
    );
  }
}

class _AggregateSiteChip extends StatelessWidget {
  final String siteName;
  const _AggregateSiteChip({required this.siteName});

  Color _resolveSiteColor(BuildContext context, String siteName) {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final sites = storage.siteConfigsCache ?? [];
      final found = sites.firstWhere(
        (s) => s.name == siteName,
        orElse: () => const SiteConfig(id: '', name: '', baseUrl: ''),
      );
      if (found.siteColor != null) return Color(found.siteColor!);
    } catch (_) {}
    final primaries = Colors.primaries;
    final color = primaries[(siteName.hashCode.abs()) % primaries.length];
    return color;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _resolveSiteColor(context, siteName),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        siteName,
        style: TextStyle(
          color: const Color.fromARGB(255, 255, 255, 255),
          fontWeight: FontWeight.w600,
          fontSize: 10,
          height: 1.2,
        ),
      ),
    );
  }
}

// 自定义左滑组件，支持固定显示按钮
class _SwipeableItem extends StatefulWidget {
  final Widget child;
  final List<Widget> Function(BuildContext context, VoidCallback close)
  actionBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isAggregateMode;

  const _SwipeableItem({
    required this.child,
    required this.actionBuilder,
    required this.isAggregateMode,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_SwipeableItem> createState() => _SwipeableItemState();
}

class _SwipeableItemState extends State<_SwipeableItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragExtent = 0;
  bool _isOpen = false;

  // 缓存 actions 列表以在拖拽回调中使用
  List<Widget> _actions = [];

  // 计算动作按钮的总宽度
  double get _actionsWidth {
    if (_actions.isEmpty) return 0;
    return _actions.length * 64.0; // 每个按钮60px + 4px间距
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // 添加动画监听器，只添加一次
    _animation.addListener(_updateDragExtent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateActions();
  }

  @override
  void didUpdateWidget(_SwipeableItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateActions();
  }

  void _updateActions() {
    _actions = widget.actionBuilder(context, _close);
  }

  @override
  void dispose() {
    _animation.removeListener(_updateDragExtent);
    _controller.dispose();
    super.dispose();
  }

  void _updateDragExtent() {
    setState(() {
      _dragExtent = _animation.value;
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_actions.isEmpty) return;

    final delta = details.primaryDelta ?? 0;
    final newDragExtent = _dragExtent + delta;

    // 限制拖拽范围：向左滑动为负值，最大滑动距离为按钮宽度
    setState(() {
      _dragExtent = newDragExtent.clamp(-_actionsWidth, 0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_actions.isEmpty) return;

    final velocity = details.primaryVelocity ?? 0;
    final threshold = _actionsWidth * 0.3;

    // 判断是否应该打开或关闭
    bool shouldOpen = false;

    if (velocity < -300) {
      // 快速向左滑动，打开
      shouldOpen = true;
    } else if (velocity > 300) {
      // 快速向右滑动，关闭
      shouldOpen = false;
    } else {
      // 根据滑动距离判断
      shouldOpen = _dragExtent.abs() > threshold;
    }

    _animateToPosition(shouldOpen);
  }

  void _animateToPosition(bool open) {
    _isOpen = open;
    final targetExtent = open ? -_actionsWidth : 0.0;

    // 如果目标位置和当前位置相同，不需要动画
    if ((_dragExtent - targetExtent).abs() < 0.1) {
      setState(() {
        _dragExtent = targetExtent;
      });
      return;
    }

    // 重新创建动画，避免状态冲突
    _animation = Tween<double>(
      begin: _dragExtent,
      end: targetExtent,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // 重置并启动动画
    _controller.reset();
    _controller.forward();
  }

  void _close() {
    if (_isOpen) {
      _animateToPosition(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isOpen) {
          _close();
        } else {
          widget.onTap?.call();
        }
      },
      onLongPress: _isOpen ? null : widget.onLongPress,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Container(
        margin: widget.isAggregateMode
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        child: ClipRect(
          child: Stack(
            children: [
              // 背景动作按钮
              if (_actions.isNotEmpty)
                Positioned(
                  right: -_actionsWidth + _dragExtent.abs(),
                  top: 0,
                  bottom: 0,
                  width: _actionsWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _actions,
                  ),
                ),
              // 主要内容
              Transform.translate(
                offset: Offset(_dragExtent, 0),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagsView extends StatelessWidget {
  final List<TagType> tags;
  final bool isTop;
  const _TagsView({required this.tags, this.isTop = false});

  Widget _buildChip(TagType tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: tag.color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        tag.content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isTop)
          Transform.rotate(
            angle: math.pi / 4,
            child: Icon(
              Icons.push_pin,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ...tags.map(_buildChip),
      ],
    );
  }
}
