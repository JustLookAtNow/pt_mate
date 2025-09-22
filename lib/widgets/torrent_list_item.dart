import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../utils/format.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 种子名称（聚合搜索模式下包含站点名称）
                    if (isAggregateMode && siteName != null)
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: ' $siteName ',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                            ),

                            TextSpan(
                              text: ' ${torrent.name}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        torrent.name,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.titleMedium?.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // 种子描述
                    Text(
                      torrent.smallDescr,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 底部信息行（优惠标签、做种/下载数、大小、下载状态）
                    Row(
                      children: [
                        // 优惠标签
                        if (torrent.discount != DiscountType.normal)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _discountColor(torrent.discount),
                              borderRadius: BorderRadius.circular(4),
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
                        _buildSeedLeechInfo(torrent.seeders, torrent.leechers),
                        const SizedBox(width: 10),
                        // 文件大小
                        Text(Formatters.dataFromBytes(torrent.sizeBytes)),
                        const Spacer(),
                        // 下载状态图标 - 仅在站点支持下载历史功能时显示
                        if (currentSite?.features.supportHistory ?? true)
                          _buildDownloadStatusIcon(torrent.downloadStatus),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 操作按钮列
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 收藏按钮 - 仅在站点支持收藏功能且非聚合搜索模式时显示
                  if (!isAggregateMode &&
                      (currentSite?.features.supportCollection ?? true))
                    IconButton(
                      onPressed: onToggleCollection,
                      icon: Icon(
                        torrent.collection
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: torrent.collection ? Colors.red : null,
                      ),
                      tooltip: torrent.collection ? '取消收藏' : '收藏',
                      padding: EdgeInsets.zero,
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
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
  String _discountText(DiscountType discount, String? endTime) {
    final baseText = discount.displayText;

    if ((discount == DiscountType.free || discount == DiscountType.twoXFree) &&
        endTime != null &&
        endTime.isNotEmpty) {
      try {
        final endDateTime = DateTime.parse(endTime);
        final now = DateTime.now();
        final difference = endDateTime.difference(now);
        final hoursLeft = difference.inHours;

        if (hoursLeft > 0) {
          return '$baseText ${hoursLeft}h';
        }
      } catch (e) {
        // 解析失败，返回基础文本
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
