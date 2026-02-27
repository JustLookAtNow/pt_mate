import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../utils/format.dart';
import 'cached_network_image.dart';
import '../utils/screen_utils.dart';

// 文件级日志实例
final Logger _logger = Logger();

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
  });

  bool _hasRatingValue(String? r) {
    if (r == null) return false;
    final t = r.trim();
    if (t.isEmpty || t == 'N/A') return false;
    final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(t);
    if (m == null) return false;
    final v = double.tryParse(m.group(1)!);
    return v != null && v > 0;
  }

  @override
  Widget build(BuildContext context) {
    // 检测是否为移动设备（屏幕宽度小于600px）
    final isMobile = MediaQuery.of(context).size.width < 600;
    // 将站点配置的 showCover 与用户全局设置做与运算
    final siteShowCover = currentSite?.features.showCover ?? true;
    final showCover = siteShowCover && (showCoverSetting ?? true);

    // 统一计算标签与清理后的描述，避免重复调用

    // final tags = TagType.matchTags(descrRef);
    // 这里的tags已经在adapter中计算好了，直接使用
    final tags = torrent.tags;

    final hasDouban = _hasRatingValue(torrent.doubanRating);
    final hasImdb = _hasRatingValue(torrent.imdbRating);
    final hasAnyRating = hasDouban || hasImdb;
    final double rightMinHeight = showCover
        ? (isMobile && hasAnyRating ? 130.0 : 100.0)
        : 70.0;

    // 构建主要内容
    Widget mainContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主体卡片内容
          Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6),
                      width: 1,
                    )
                  : null,
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 封面截图和创建时间（在 showCover 为 true 时显示）
                        if (showCover && (suspendImageLoading != true))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 封面截图
                              Container(
                                width: 70,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: GestureDetector(
                                  onTap: () async {
                                    if (torrent.cover.isNotEmpty) {
                                      // 先取消当前焦点（如搜索框），防止 Dialog 关闭后恢复
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      await showDialog(
                                        context: context,
                                        builder: (ctx) => Dialog(
                                          child: CachedNetworkImage(
                                            imageUrl: torrent.cover,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      );
                                      // Dialog 关闭后焦点恢复机制会在下一帧重新聚焦之前的控件，
                                      // 必须在 postFrameCallback 中再次取消
                                      if (context.mounted) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                            });
                                      }
                                    }
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: torrent.cover.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: torrent.cover,
                                            width: 70,
                                            height: 100,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) {
                                                return child;
                                              }
                                              return Container(
                                                width: 70,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '加载中',
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  if (kDebugMode) {
                                                    _logger.w('图片加载失败: $error');
                                                  }
                                                  return Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.image_outlined,
                                                        size: 24,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '加载失败',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.image_outlined,
                                                size: 24,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '暂无',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                              // 评分模块（仅移动端左列显示；桌面端在右侧标签后显示）
                              // const SizedBox(height: 8),
                              if (isMobile)
                                Container(
                                  width: 70,
                                  margin: const EdgeInsets.only(right: 8),
                                  child: Column(
                                    children: [
                                      // 豆瓣评分
                                      if (hasDouban)
                                        Container(
                                          width: 70,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF007711),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '豆 ${torrent.doubanRating}',
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      // IMDB评分
                                      if (hasImdb)
                                        Container(
                                          width: 70,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF5C518),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'IMDB ${torrent.imdbRating}',
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.black,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: rightMinHeight,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // 标签与评分行（桌面端统一追加评分；移动端在关闭封面时追加）
                                if (tags.isNotEmpty ||
                                    (!isMobile && hasAnyRating) ||
                                    (isMobile && !showCover && hasAnyRating))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(child: _TagsView(tags: tags)),
                                        if (!isMobile || !showCover) ...[
                                          if (hasDouban)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF007711),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '豆 ${torrent.doubanRating}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if (hasImdb)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5C518),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'IMDB ${torrent.imdbRating}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                // 种子名称（聚合搜索模式下包含站点名称）
                                if (isAggregateMode && siteName != null)
                                  Tooltip(
                                    message: '$siteName ${torrent.name}',
                                    // 默认触发：桌面/网页为悬停，移动端为长按
                                    waitDuration: const Duration(
                                      milliseconds: 400,
                                    ),
                                    showDuration: const Duration(seconds: 5),
                                    child: RichText(
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        children: [
                                          WidgetSpan(
                                            alignment:
                                                PlaceholderAlignment.middle,
                                            child: _AggregateSiteChip(
                                              siteName: siteName!,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' ${torrent.name}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.titleMedium?.color,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Tooltip(
                                    message: torrent.name,
                                    // 默认触发：桌面/网页为悬停，移动端为长按
                                    waitDuration: const Duration(
                                      milliseconds: 400,
                                    ),
                                    showDuration: const Duration(seconds: 5),
                                    child: RichText(
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: torrent.name,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.titleMedium?.color,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                // 种子描述（使用清理后的描述）
                                Text(
                                  torrent.smallDescr,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                        fontSize: 12,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '发布于 ${Formatters.formatTorrentCreatedDate(torrent.createdDate)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // 底部信息行（优惠标签、做种/下载数、大小、下载状态）
                                Row(
                                  children: [
                                    // 优惠标签
                                    if (torrent.discount != DiscountType.normal)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _discountColor(
                                            torrent.discount,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          _discountText(
                                            torrent.discount,
                                            torrent.discountEndTime,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    if (torrent.discount != DiscountType.normal)
                                      const SizedBox(width: 6),
                                    // 做种/下载数信息
                                    _buildSeedLeechInfo(
                                      torrent.seeders,
                                      torrent.leechers,
                                    ),
                                    const SizedBox(width: 10),
                                    // 文件大小
                                    Text(
                                      Formatters.dataFromBytes(
                                        torrent.sizeBytes,
                                      ),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    // 评论数 - 仅在 mteam 和 nexusphp 类型站点显示
                                    if (currentSite?.siteType ==
                                            SiteType.mteam ||
                                        currentSite?.siteType ==
                                            SiteType.nexusphp) ...[
                                      const SizedBox(width: 10),
                                      Icon(
                                        Icons.comment,
                                        size: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${torrent.comments}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                    const Spacer(),
                                    // 下载状态图标 - 仅在站点支持下载历史功能时显示
                                    if (currentSite?.features.supportHistory ??
                                        true)
                                      _buildDownloadStatusIcon(
                                        torrent.downloadStatus,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 桌面端显示操作按钮
                        if (!isMobile) ...[
                          const SizedBox(width: 4),
                          Column(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 收藏按钮 - 仅在站点支持收藏功能时显示
                              if (currentSite?.features.supportCollection ??
                                  true)
                                IconButton(
                                  onPressed: onToggleCollection,
                                  icon: Icon(
                                    torrent.collection
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: torrent.collection
                                        ? Colors.red
                                        : null,
                                  ),
                                  tooltip: torrent.collection ? '取消收藏' : '收藏',
                                  padding: EdgeInsets.all(10),
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                ),
                              // 下载按钮 - 仅在站点支持下载功能时显示
                              if (currentSite?.features.supportDownload ?? true)
                                IconButton(
                                  onPressed: onDownload,
                                  icon: const Icon(Icons.download_outlined),
                                  tooltip: '下载',
                                  padding: EdgeInsets.all(10),
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 置顶标记（右上角）
          if (torrent.isTop)
            Positioned(
              top: -3,
              right: -3,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Icon(
                  Icons.push_pin,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    // 移动设备使用自定义左滑功能
    if (isMobile) {
      return _SwipeableItem(
        onTap: onTap,
        onLongPress: onLongPress,
        actions: _buildSwipeActions(context),
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
  List<Widget> _buildSwipeActions(BuildContext context) {
    List<Widget> actions = [];

    // 添加收藏按钮（如果支持）
    if (currentSite?.features.supportCollection ?? true) {
      actions.add(
        Container(
          width: 60,
          margin: const EdgeInsets.only(left: 4),
          child: Material(
            color: torrent.collection
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
              onTap: onToggleCollection,
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
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                : Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onDownload,
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

    return actions;
  }

  /// 获取优惠类型对应的颜色
  Color _discountColor(DiscountType discount) {
    switch (discount.colorType) {
      case DiscountColorType.green:
        return Colors.green;
      case DiscountColorType.yellow:
        return Colors.amber;
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

  /// 构建做种/下载数信息组件
  Widget _buildSeedLeechInfo(int seeders, int leechers) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.arrow_upward, color: Colors.green, size: 16),
        Text('$seeders', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        const Icon(Icons.arrow_downward, color: Colors.red, size: 16),
        Text('$leechers', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  /// 构建下载状态图标
  Widget _buildDownloadStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return const Icon(Icons.download_done, color: Colors.green, size: 20);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        );
      case DownloadStatus.none:
        return const SizedBox(width: 20); // 占位，保持布局一致
    }
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
    final color = _resolveSiteColor(context, siteName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        ' $siteName ',
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ) ??
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

// 自定义左滑组件，支持固定显示按钮
class _SwipeableItem extends StatefulWidget {
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isAggregateMode;

  const _SwipeableItem({
    required this.child,
    required this.actions,
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

  // 计算动作按钮的总宽度
  double get _actionsWidth {
    if (widget.actions.isEmpty) return 0;
    return widget.actions.length * 64.0; // 每个按钮60px + 4px间距
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
    if (widget.actions.isEmpty) return;

    final delta = details.primaryDelta ?? 0;
    final newDragExtent = _dragExtent + delta;

    // 限制拖拽范围：向左滑动为负值，最大滑动距离为按钮宽度
    setState(() {
      _dragExtent = newDragExtent.clamp(-_actionsWidth, 0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (widget.actions.isEmpty) return;

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
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: ClipRect(
          child: Stack(
            children: [
              // 背景动作按钮
              if (widget.actions.isNotEmpty)
                Positioned(
                  right: -_actionsWidth + _dragExtent.abs(),
                  top: 0,
                  bottom: 0,
                  width: _actionsWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: widget.actions,
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

class _TagsView extends StatefulWidget {
  final List<TagType> tags;
  const _TagsView({required this.tags});
  @override
  State<_TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends State<_TagsView> {
  bool _expanded = false;
  bool _overflow = false;

  Widget _buildChip(TagType tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
        ),
      ),
    );
  }

  Widget _buildWrap() {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: widget.tags.map(_buildChip).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measureChild = Offstage(
          offstage: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: _MeasureSize(
              onChange: (s) {
                if (!_expanded) {
                  final overflow = s.height > 18.0 + 0.1;
                  if (overflow != _overflow) {
                    if (mounted) {
                      setState(() {
                        _overflow = overflow;
                      });
                    }
                  }
                }
              },
              child: _buildWrap(),
            ),
          ),
        );

        if (_expanded) {
          return _buildWrap();
        }

        return Row(
          children: [
            Expanded(
              child: SizedBox(height: 18, child: ClipRect(child: _buildWrap())),
            ),
            if (_overflow && !ScreenUtils.isLargeScreen(context)) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expanded = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
            measureChild,
          ],
        );
      },
    );
  }
}

typedef SizeChangedCallback = void Function(Size size);

class _MeasureSize extends SingleChildRenderObjectWidget {
  final SizeChangedCallback onChange;
  const _MeasureSize({required this.onChange, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  SizeChangedCallback onChange;
  Size? _prevSize;
  _RenderMeasureSize(this.onChange);
  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? size;
    if (_prevSize == null || _prevSize != newSize) {
      _prevSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange(newSize);
      });
    }
  }
}
