import '../utils/screen_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/theme/app_tokens.dart';
import 'dart:math' as math;

import '../utils/format.dart';
import 'cached_network_image.dart';

// Helper method to parse rating
// Using a static final RegExp to avoid recompiling the pattern on every call, improving performance.
final RegExp _ratingRegExp = RegExp(r'([0-9]+(?:\.[0-9]+)?)');

const double _mobileCoverWidth = 64;
const double _mobileCoverHeight = 90;
const double _desktopCoverWidth = 56;
const double _desktopCoverHeight = 80;
const double _desktopNoCoverSideHeight = 72;

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
    final effectiveShowCover = showCover && (suspendImageLoading != true);
    final isCompactDesktopNoCover = !isMobile && !effectiveShowCover;
    final double desktopSideHeight = effectiveShowCover
        ? _desktopCoverHeight
        : _desktopNoCoverSideHeight;

    // 构建主要内容
    Widget mainContent = Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 4 : 8,
        vertical: isCompactDesktopNoCover ? 2 : 3,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主体卡片内容
          Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
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
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 3 : 4,
                      vertical: isCompactDesktopNoCover ? 2 : 4,
                    ),
                    child: _TorrentListItemRow(
                      torrent: torrent,
                      currentSite: currentSite,
                      isAggregateMode: isAggregateMode,
                      siteName: siteName,
                      isMobile: isMobile,
                      effectiveShowCover: effectiveShowCover,
                      hasDouban: hasDouban,
                      hasImdb: hasImdb,
                      hasAnyRating: hasAnyRating,
                      desktopSideHeight: desktopSideHeight,
                      batchOperationType: batchOperationType,
                      batchItemState: batchItemState,
                      batchErrorMessage: batchErrorMessage,
                      onRetryBatchAction: onRetryBatchAction,
                      onToggleCollection: onToggleCollection,
                      onDownload: onDownload,
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

class _TorrentListItemRow extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final bool isAggregateMode;
  final String? siteName;
  final bool isMobile;
  final bool effectiveShowCover;
  final bool hasDouban;
  final bool hasImdb;
  final bool hasAnyRating;
  final double desktopSideHeight;
  final BatchOperationType? batchOperationType;
  final BatchItemState batchItemState;
  final String? batchErrorMessage;
  final VoidCallback? onRetryBatchAction;
  final VoidCallback? onToggleCollection;
  final VoidCallback? onDownload;

  const _TorrentListItemRow({
    required this.torrent,
    this.currentSite,
    required this.isAggregateMode,
    this.siteName,
    required this.isMobile,
    required this.effectiveShowCover,
    required this.hasDouban,
    required this.hasImdb,
    required this.hasAnyRating,
    required this.desktopSideHeight,
    this.batchOperationType,
    required this.batchItemState,
    this.batchErrorMessage,
    this.onRetryBatchAction,
    this.onToggleCollection,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: isMobile
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: [
        // 封面截图和创建时间（在 showCover 为 true 时显示）
        if (effectiveShowCover)
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
            showCover: effectiveShowCover,
            hasDouban: hasDouban,
            hasImdb: hasImdb,
            hasAnyRating: hasAnyRating,
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
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Container(
              width: 1,
              height: math.max(60, desktopSideHeight - 16),
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: math.max(60, desktopSideHeight - 8),
            child: TorrentActions(
              torrent: torrent,
              currentSite: currentSite,
              onToggleCollection: onToggleCollection,
              onDownload: onDownload,
              compact: !effectiveShowCover,
            ),
          ),
        ],
      ],
    );

    return isMobile ? row : IntrinsicHeight(child: row);
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
    this.batchOperationType,
    this.batchItemState = BatchItemState.idle,
    this.batchErrorMessage,
    this.onRetryBatchAction,
  });

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
    final isCompactDesktopNoCover = !isMobile && !showCover;
    final showInlineRatings = !showCover && hasAnyRating;
    final showInlineDiscount =
        !showCover && torrent.discount != DiscountType.normal;
    final hasHeaderRow =
        torrent.isTop ||
        torrent.tags.isNotEmpty ||
        showInlineRatings ||
        showInlineDiscount;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: isMobile ? AppSpacing.xs : 0,
        top: isCompactDesktopNoCover ? 0 : 2,
        bottom: isCompactDesktopNoCover ? 0 : 2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签 / 置顶 / 内联优惠与评分（无封面时）
          if (hasHeaderRow)
            Padding(
              padding: EdgeInsets.only(bottom: isCompactDesktopNoCover ? 1 : 2),
              child: _TagsRatingRow(
                tags: torrent.tags,
                isTop: torrent.isTop,
                discountBadge: showInlineDiscount
                    ? _DiscountBadge(torrent: torrent)
                    : null,
                ratingBadges: showInlineRatings
                    ? _RatingBadges(
                        torrent: torrent,
                        hasDouban: hasDouban,
                        hasImdb: hasImdb,
                        compact: isMobile,
                      )
                    : null,
              ),
            ),
          Tooltip(
            message: torrent.name,
            child: Text(
              torrent.name,
              maxLines: isMobile ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).textTheme.titleMedium?.color,
                fontWeight: FontWeight.bold,
                fontSize: AppFontSize.title,
                height: isCompactDesktopNoCover ? 1.15 : 1.2,
              ),
            ),
          ),
          SizedBox(height: isCompactDesktopNoCover ? 1 : 2),
          // Subtitle
          Text(
            torrent.smallDescr,
            maxLines: isMobile ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: isCompactDesktopNoCover ? 1.15 : 1.2,
            ),
          ),
          SizedBox(height: isCompactDesktopNoCover ? 2 : 4),
          // 底部内联统计行
          _StatsRow(
            torrent: torrent,
            currentSite: currentSite,
            compact: isCompactDesktopNoCover,
          ),
          if (batchStatus != null) ...[const SizedBox(height: 4), batchStatus],
        ],
      ),
    );
  }
}

/// 底部内联统计行：做种/下载/大小/发布时间 + 评论数与下载历史状态
class _StatsRow extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final bool compact;

  const _StatsRow({
    required this.torrent,
    this.currentSite,
    this.compact = false,
  });

  Widget _downloadStatusIcon(DownloadStatus status, AppSemanticColors colors) {
    switch (status) {
      case DownloadStatus.completed:
        return Tooltip(
          message: '已完成',
          child: Icon(Icons.download_done, color: colors.seeders, size: 15),
        );
      case DownloadStatus.downloading:
        return const Tooltip(
          message: '下载中',
          child: SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case DownloadStatus.none:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final metaStyle = TextStyle(
      fontSize: AppFontSize.meta,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: compact ? 1.15 : 1.2,
    );
    final showComments =
        currentSite?.siteType == SiteType.mteam ||
        currentSite?.siteType == SiteType.nexusphp;
    final showHistory =
        (currentSite?.features.supportHistory ?? true) &&
        torrent.downloadStatus != DownloadStatus.none;

    return DefaultTextStyle.merge(
      style: metaStyle,
      child: Row(
        children: [
          Icon(Icons.arrow_upward, color: colors.seeders, size: 12),
          const SizedBox(width: 2),
          Text('${torrent.seeders}'),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.arrow_downward, color: colors.leechers, size: 12),
          const SizedBox(width: 2),
          Text('${torrent.leechers}'),
          const SizedBox(width: AppSpacing.sm),
          _SizeText(sizeBytes: torrent.sizeBytes),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              Formatters.formatTorrentCreatedDate(torrent.createdDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showComments) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chat_bubble_outline,
              size: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text('${torrent.comments}'),
          ],
          if (showHistory) ...[
            const SizedBox(width: AppSpacing.sm),
            _downloadStatusIcon(torrent.downloadStatus, colors),
          ],
        ],
      ),
    );
  }
}

class _SizeText extends StatelessWidget {
  final int sizeBytes;

  const _SizeText({required this.sizeBytes});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        Formatters.dataFromBytes(sizeBytes),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// 优惠标签徽章。[solid] 为 true 时用于封面角标（不透明底、白字），
/// 否则为标签行内的浅色填充样式。
class _DiscountBadge extends StatelessWidget {
  final TorrentItem torrent;
  final bool solid;

  const _DiscountBadge({required this.torrent, this.solid = false});

  Color _color(AppSemanticColors colors) {
    switch (torrent.discount.colorType) {
      case DiscountColorType.green:
        return colors.discountFree;
      case DiscountColorType.yellow:
        return colors.discountPercent;
      case DiscountColorType.blue:
        return colors.discountOther;
      case DiscountColorType.none:
        return Colors.grey;
    }
  }

  String _text() {
    final baseText = torrent.discount.displayText;
    final endTime = torrent.discountEndTime;
    if (torrent.discount != DiscountType.normal && endTime != null) {
      final hoursLeft = endTime.difference(DateTime.now()).inHours;
      if (hoursLeft > 0) return '$baseText ${hoursLeft}h';
    }
    return baseText;
  }

  @override
  Widget build(BuildContext context) {
    // 封面角标叠在图片上，需要不透明底色保证可读，
    // 固定使用饱和度较高的浅色版语义色 + 白字。
    final color = solid
        ? _color(AppSemanticColors.light)
        : _color(context.semanticColors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.15),
        borderRadius: solid
            ? const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.sm),
                bottomRight: Radius.circular(AppRadius.sm),
              )
            : BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _text(),
        style: TextStyle(
          color: solid ? Colors.white : color,
          fontSize: AppFontSize.badge,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _RatingBadges extends StatelessWidget {
  final TorrentItem torrent;
  final bool hasDouban;
  final bool hasImdb;
  final bool compact;

  const _RatingBadges({
    required this.torrent,
    required this.hasDouban,
    required this.hasImdb,
    this.compact = false,
  });

  Widget _buildBadge({
    required String text,
    required Color backgroundColor,
    required Color foregroundColor,
    BorderRadius? borderRadius,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 6,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius ?? BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          color: foregroundColor,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasImdb)
          _buildBadge(
            text: 'IMDB ${torrent.imdbRating}',
            backgroundColor: colors.imdbBadge,
            foregroundColor: colors.onImdbBadge,
          ),
        if (hasDouban)
          _buildBadge(
            text: '豆 ${torrent.doubanRating}',
            backgroundColor: colors.doubanBadge,
            foregroundColor: colors.onDoubanBadge,
          ),
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

  double get _coverWidth => isMobile ? _mobileCoverWidth : _desktopCoverWidth;

  double get _coverHeight =>
      isMobile ? _mobileCoverHeight : _desktopCoverHeight;

  Widget _buildCoverPlaceholder(
    BuildContext context, {
    required Widget icon,
    required String text,
  }) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: _coverWidth,
      height: _coverHeight,
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
    return SizedBox(
      width: _coverWidth,
      height: _coverHeight,
      // margin: const EdgeInsets.only(right: 12),
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
                        width: _coverWidth,
                        height: _coverHeight,
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
          if (torrent.discount != DiscountType.normal)
            Positioned(
              left: 0,
              top: 0,
              child: _DiscountBadge(torrent: torrent, solid: true),
            ),
          if (hasDouban || hasImdb)
            Positioned(
              left: 0,
              bottom: 0,
              child: _CoverRatingBadges(
                torrent: torrent,
                hasDouban: hasDouban,
                hasImdb: hasImdb,
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverRatingBadges extends StatelessWidget {
  final TorrentItem torrent;
  final bool hasDouban;
  final bool hasImdb;

  const _CoverRatingBadges({
    required this.torrent,
    required this.hasDouban,
    required this.hasImdb,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImdb)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.imdbBadge,
              borderRadius: BorderRadius.only(
                topRight: const Radius.circular(6),
                bottomLeft: hasDouban ? Radius.zero : const Radius.circular(6),
              ),
            ),
            child: Text(
              'IMDB ${torrent.imdbRating}',
              style: TextStyle(
                fontSize: 10,
                color: colors.onImdbBadge,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (hasDouban)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.doubanBadge,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: Text(
              '豆 ${torrent.doubanRating}',
              style: TextStyle(
                fontSize: 10,
                color: colors.onDoubanBadge,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _TagsRatingRow extends StatelessWidget {
  final List<TagType> tags;
  final bool isTop;
  final Widget? ratingBadges;
  final Widget? discountBadge;

  const _TagsRatingRow({
    required this.tags,
    this.isTop = false,
    this.ratingBadges,
    this.discountBadge,
  });

  @override
  Widget build(BuildContext context) {
    final hasTags = isTop || tags.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (discountBadge != null) ...[
          discountBadge!,
          const SizedBox(width: 6),
        ],
        if (hasTags)
          Expanded(
            child: _TagsView(tags: tags, isTop: isTop),
          )
        else
          const Spacer(),
        if (ratingBadges != null) ...[
          if (hasTags) const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: ratingBadges,
          ),
        ],
      ],
    );
  }
}

class TorrentActions extends StatelessWidget {
  final TorrentItem torrent;
  final SiteConfig? currentSite;
  final VoidCallback? onToggleCollection;
  final VoidCallback? onDownload;
  final bool compact;

  const TorrentActions({
    super.key,
    required this.torrent,
    this.currentSite,
    this.onToggleCollection,
    this.onDownload,
    this.compact = false,
  });

  ButtonStyle get _compactIconButtonStyle {
    final size = compact ? 32.0 : 36.0;
    return IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      fixedSize: Size.square(size),
      minimumSize: Size.square(size),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

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
            iconSize: compact ? 18 : 20,
            style: _compactIconButtonStyle,
          ),
        // 下载按钮 - 仅在站点支持下载功能时显示
        if (currentSite?.features.supportDownload ?? true)
          IconButton(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载',
            iconSize: compact ? 18 : 20,
            style: _compactIconButtonStyle,
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
