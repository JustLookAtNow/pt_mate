import 'package:intl/intl.dart';

/// 格式化工具类，用于格式化文件大小、速度和时间
class FormatUtil {
  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// 格式化速度
  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
    }
  }

  /// 格式化剩余时间
  static String formatEta(int seconds) {
    if (seconds < 0) {
      return '未知';
    }

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  /// 解析字符串为整数
  /// 先判断有没有小数点，有的话则截取整数部分，然后移除掉所有的非数字字符，最后返回int.tryParse的结果
  static int? parseInt(dynamic value) {
    if (value == null) return null;
    String str = value.toString();
    if (str.isEmpty) return null;

    // 如果包含小数点，截取整数部分
    if (str.contains('.')) {
      str = str.substring(0, str.indexOf('.'));
    }

    // 移除所有非数字字符
    str = str.replaceAll(RegExp(r'\D'), '');

    return int.tryParse(str);
  }
}

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
  static String bonus(num bonus) {
    final int v = bonus.toInt();
    final int absV = v.abs();
    if (absV >= 1000000) {
      return '${v ~/ 1000000} M';
    }
    if (absV >= 1000) {
      return '${v ~/ 1000} K';
    }
    return v.toString();
  }

  // 新增：格式化种子创建时间为距离现在过了多久
  static String formatTorrentCreatedDate(DateTime date) {
    try {
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
          return '$years 年 $months 月 前';
        }
        return '$years 年 前';
      }

      if (months > 0) {
        if (days > 0) {
          return '$months 月 $days 天 前';
        }
        return '$months 月 前';
      }

      if (days > 0) {
        if (hours > 0) {
          return '$days 天 $hours 小时 前';
        }
        return '$days 天 前';
      }

      if (hours > 0) {
        if (minutes > 0) {
          return '$hours 小时 $minutes 分钟 前';
        }
        return '$hours 小时 前';
      }

      // 最小单位为分钟
      if (minutes > 0) {
        return '$minutes 分钟 前';
      }

      return '刚刚'; // 不足1分钟显示为刚刚
    } catch (e) {
      return "- -";
    }
  }

  static String? laterDateTime(String? a, String? b) {
    DateTime? d1;
    DateTime? d2;
    try {
      d1 = a != null && a.isNotEmpty ? DateTime.parse(a) : null;
    } catch (_) {}
    try {
      d2 = b != null && b.isNotEmpty ? DateTime.parse(b) : null;
    } catch (_) {}
    if (d1 != null && d2 != null) {
      return d1.isAfter(d2) ? a : b;
    }
    return a ?? b;
  }

  static DateTime parseDateTimeCustom(
    String? dateStr, {
    String? format,
    String? zone,
  }) {
    if (dateStr == null || dateStr.isEmpty) return DateTime.now();

    try {
      String actualZone = zone ?? "+08:00";
      DateTime parsed;

      if (format != null && format.isNotEmpty) {
        // 使用 DateFormat 解析自定义格式
        parsed = DateFormat(format).parse(dateStr.trim());
      } else {
        // 回退逻辑：处理常见的 "yyyy-MM-dd HH:mm:ss" 或标准 ISO 格式
        String normalizedDate = dateStr.trim();
        if (normalizedDate.length >= 19 && normalizedDate[10] == ' ') {
          normalizedDate = normalizedDate.replaceRange(10, 11, 'T');
        }

        if (normalizedDate.contains(RegExp(r'Z|[+-]\d{2}:?\d{2}$'))) {
          return DateTime.parse(normalizedDate).toLocal();
        } else {
          return DateTime.parse("$normalizedDate$actualZone").toLocal();
        }
      }

      // 修正时区：将 DateFormat 解析出的不带时区的时间视为指定时区的时间，再转换为本地时间
      String iso = parsed
          .toIso8601String()
          .split('.')
          .first; // 取 yyyy-MM-ddTHH:mm:ss 部分
      if (iso.contains('.')) iso = iso.split('.').first;

      return DateTime.parse("$iso$actualZone").toLocal();
    } catch (e) {
      try {
        return DateTime.parse(dateStr).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }
  }
}
