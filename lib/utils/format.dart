import 'package:intl/intl.dart';

class Formatters {
  static final NumberFormat _num2 = NumberFormat('#,##0.00');

  // 输入单位为 B（字节），格式化为 GB 或 TB（保留两位小数）
  static String dataFromBytes(num bytes) {
    final double gb = bytes / (1024 * 1024 * 1024); // B -> GB
    if (gb >= 1024) {
      final tb = gb / 1024; // GB -> TB
      return '${_num2.format(tb)} TB';
    }
    return '${_num2.format(gb)} GB';
  }

  // 新增：输入单位为 B/s（字节每秒），格式化为 KB/s、MB/s 或 GB/s
  static String speedFromBytesPerSec(num bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toInt()} B/s';
    final kb = bytesPerSec / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB/s';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB/s';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB/s';
  }

  static String shareRate(num rate) => _num2.format(rate);
  static String bonus(num bonus) => _num2.format(bonus);

  // 新增：格式化种子创建时间为距离现在过了多久
  static String formatTorrentCreatedDate(String createdDate) {
    try {
      final date = DateTime.parse(createdDate);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      // 计算各个时间单位
      final years = difference.inDays ~/ 365;
      final months = (difference.inDays % 365) ~/ 30;
      final days = difference.inDays % 30;
      final hours = difference.inHours % 24;
      final minutes = difference.inMinutes % 60;
      
      // 按优先级返回两段显示
      if (years > 0) {
        if (months > 0) {
          return '$years 年 $months 月';
        }
        return '$years 年';
      }
      
      if (months > 0) {
        if (days > 0) {
          return '$months 月 $days 天';
        }
        return '$months 月';
      }
      
      if (days > 0) {
        if (hours > 0) {
          return '$days 天 $hours 小时';
        }
        return '$days 天';
      }
      
      if (hours > 0) {
        if (minutes > 0) {
          return '$hours 小时 $minutes 分钟';
        }
        return '$hours 小时';
      }
      
      // 最小单位为分钟
      if (minutes > 0) {
        return '$minutes 分钟';
      }
      
      return '刚刚'; // 不足1分钟显示为刚刚
    } catch (e) {
      return "- -"; // 解析失败时返回原始字符串
    }
  }
}
