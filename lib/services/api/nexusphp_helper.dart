import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../../models/app_models.dart';

/// NexusPHP相关站点的公共辅助方法
mixin NexusPHPHelper {
  /// 标签映射配置
  Map<String, String>? get tagMapping;

  /// 优惠类型映射配置
  Map<String, String>? get discountMapping;

  /// 从字符串解析标签类型
  TagType? parseTagType(String? str) {
    if (str == null || str.isEmpty) return null;

    final mapping = tagMapping ?? {};
    final enumName = mapping[str];

    if (enumName != null) {
      for (final type in TagType.values) {
        if (type.name.toLowerCase() == enumName.toLowerCase()) {
          return type;
        }
        if (type.content == enumName) {
          return type;
        }
      }
    }
    return null;
  }

  /// 从字符串解析优惠类型
  DiscountType parseDiscountType(String? str) {
    if (str == null || str.isEmpty) return DiscountType.normal;

    final mapping = discountMapping ?? {};
    final enumValue = mapping[str];

    if (enumValue != null) {
      for (final type in DiscountType.values) {
        if (type.value == enumValue) {
          return type;
        }
      }
    }

    return DiscountType.normal;
  }

  /// 生成下载哈希值
  ///
  /// 参数:
  /// - [passkey] 用户的passkey
  /// - [id] 种子ID
  /// - [userid] 用户ID
  ///
  /// 返回: JWT编码的下载令牌
  String getDownLoadHash(String passkey, String id, String userid) {
    // 生成MD5密钥: md5(passkey + 当前日期(Ymd) + userid)
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final keyString = passkey + dateStr + userid;
    final keyBytes = utf8.encode(keyString);
    final digest = md5.convert(keyBytes);
    final key = digest.toString();

    // 创建JWT payload
    final payload = {
      'id': id,
      'exp':
          (DateTime.now().millisecondsSinceEpoch / 1000).floor() +
          3600, // 1小时后过期
    };

    // 使用HS256算法生成JWT
    final jwt = JWT(payload);
    final token = jwt.sign(SecretKey(key), algorithm: JWTAlgorithm.HS256);

    return token;
  }
}
