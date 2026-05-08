
import '../../models/app_models.dart';
import '../../utils/format.dart';
import 'base_web_adapter.dart';

/// 字段提取配置
/// 与现有 JSON 配置 100% 兼容的 Dart 表示
class FieldConfig {
  final String? selector;
  final String? attribute;
  final Map<String, dynamic>? filter;
  final dynamic defaultValue;
  final bool required;
  final String? value;

  const FieldConfig({
    this.selector,
    this.attribute,
    this.filter,
    this.defaultValue,
    this.required = false,
    this.value,
  });

  /// 从 JSON/Map 构造，兼容现有配置格式
  factory FieldConfig.fromJson(Map<String, dynamic> json) {
    return FieldConfig(
      selector: json['selector'] as String?,
      attribute: json['attribute'] as String?,
      filter: json['filter'] as Map<String, dynamic>?,
      defaultValue: json['defaultValue'],
      required: json['required'] as bool? ?? false,
      value: json['value'] as String?,
    );
  }

  /// 转换为 Map，用于传给 BaseWebAdapterMixin.extractFieldValue
  Map<String, dynamic> toJson() => {
    if (selector != null) 'selector': selector,
    if (attribute != null) 'attribute': attribute,
    if (filter != null) 'filter': filter,
    if (value != null) 'value': value,
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (required) 'required': required,
  };

  /// 是否配置了 value 模板
  bool get hasValue => value != null && value!.isNotEmpty;
}

/// 提取结果封装
/// 提供链式类型转换，避免业务层重复的空值检查
class ExtractedValue {
  final String? raw;
  final bool found;

  const ExtractedValue._(this.raw, this.found);

  factory ExtractedValue.missing() => const ExtractedValue._(null, false);

  factory ExtractedValue.fromString(String? value) {
    if (value == null || value.isEmpty) {
      return const ExtractedValue._(null, false);
    }
    return ExtractedValue._(value, true);
  }

  /// 原始字符串值
  String? get string => raw;

  /// 非空字符串，未找到时返回空字符串
  String get stringOrEmpty => raw ?? '';

  /// 解析为整数
  int? get intValue => raw != null ? FormatUtil.parseInt(raw) : null;

  /// 解析为整数，带默认值
  int intValueOr(int defaultValue) => intValue ?? defaultValue;

  /// 解析为 double
  double? get doubleValue =>
      raw != null ? double.tryParse(raw!.replaceAll(',', '')) : null;

  /// 解析日期时间
  DateTime? parseDateTime({String? format, String? zone, String? fieldName}) {
    if (raw == null || raw!.isEmpty) return null;
    try {
      return Formatters.parseDateTimeCustom(
        raw,
        format: format,
        zone: zone,
        fieldName: fieldName,
      );
    } catch (_) {
      return null;
    }
  }

  /// 是否找到有效值
  bool get hasValue => found && raw != null && raw!.isNotEmpty;

  /// 布尔判断：值存在即为 true（用于 collection、isTop 等字段）
  bool get asBool => found;

  @override
  String toString() => 'ExtractedValue(raw: $raw, found: $found)';
}

/// 类型转换工具集合
/// 纯函数，Isolate 安全
class TypedConverter {
  static final RegExp _sizeRegExp = RegExp(r'([\d.]+)\s*(\w+)');

  /// 解析文件大小字符串为字节数
  /// 支持: B, KB/KiB, MB/MiB, GB/GiB, TB/TiB
  static int parseSizeToBytes(String? sizeText) {
    if (sizeText == null || sizeText.isEmpty) return 0;

    final match = _sizeRegExp.firstMatch(sizeText);
    if (match == null) return 0;

    final sizeValue = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2)?.toUpperCase() ?? 'B';

    switch (unit) {
      case 'KB':
      case 'KIB':
        return (sizeValue * 1024).round();
      case 'MB':
      case 'MIB':
        return (sizeValue * 1024 * 1024).round();
      case 'GB':
      case 'GIB':
        return (sizeValue * 1024 * 1024 * 1024).round();
      case 'TB':
      case 'TIB':
        return (sizeValue * 1024 * 1024 * 1024 * 1024).round();
      default:
        return sizeValue.round();
    }
  }

  /// 解析下载状态文本
  static DownloadStatus parseDownloadStatus(String? text) {
    if (text == null || text.isEmpty) return DownloadStatus.none;

    final percentInt = FormatUtil.parseInt(text);
    if (percentInt == null) return DownloadStatus.none;

    if (percentInt == 100) return DownloadStatus.completed;
    return DownloadStatus.downloading;
  }

  /// 解析优惠类型
  static DiscountType parseDiscount(
    String? raw,
    Map<String, String> mapping,
  ) {
    if (raw == null || raw.isEmpty) return DiscountType.normal;

    final enumValue = mapping[raw];
    if (enumValue == null) return DiscountType.normal;

    for (final type in DiscountType.values) {
      if (type.value == enumValue) return type;
    }
    return DiscountType.normal;
  }

  /// 解析标签类型
  static TagType? parseTagType(String? raw, Map<String, String> mapping) {
    if (raw == null || raw.isEmpty) return null;

    final enumName = mapping[raw];
    if (enumName == null) return null;

    for (final type in TagType.values) {
      if (type.name.toLowerCase() == enumName.toLowerCase()) return type;
      if (type.content == enumName) return type;
    }
    return null;
  }

  /// 组合解析标签：从名称+描述自动匹配 + 映射标签
  static List<TagType> parseTags(
    String torrentName,
    String description,
    List<String> rawTagList,
    Map<String, String> mapping,
  ) {
    final tags = TagType.matchTags('$torrentName $description');

    for (final tagStr in rawTagList) {
      final mappedTag = parseTagType(tagStr, mapping);
      if (mappedTag != null && !tags.contains(mappedTag)) {
        tags.add(mappedTag);
      }
    }

    return tags;
  }

  /// 确保 URL 为绝对路径
  static String resolveUrl(String? relativeUrl, String baseUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http')) return relativeUrl;

    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final separator = relativeUrl.startsWith('/') ? '' : '/';
    return '$cleanBase$separator$relativeUrl';
  }

  /// 处理下载链接模板替换
  static String resolveDownloadUrl(
    String template,
    String torrentId,
    String passKey,
    String baseUrl, {
    String? userId,
  }) {
    var url = template;
    url = url.replaceAll('{torrentId}', torrentId);
    url = url.replaceAll('{passKey}', passKey);
    if (userId != null) {
      url = url.replaceAll('{userId}', userId);
    }
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    url = url.replaceAll('{baseUrl}', cleanBase);
    return url;
  }
}

/// 声明式 HTML 提取器
/// 基于 BaseWebAdapterMixin 提供的高层封装
class HtmlExtractor with BaseWebAdapterMixin {
  /// 从单个元素提取字段
  Future<ExtractedValue> extractField(
    dynamic element,
    FieldConfig config,
  ) async {
    final values = await extractFieldValue(element, config.toJson());
    if (values.isEmpty) {
      if (config.defaultValue != null) {
        return ExtractedValue.fromString(config.defaultValue.toString());
      }
      return ExtractedValue.missing();
    }
    return ExtractedValue.fromString(values.first);
  }

  /// 提取整行/整组字段
  /// 返回字段名到提取值的映射
  Future<Map<String, ExtractedValue>> extractRow(
    dynamic rowElement,
    Map<String, FieldConfig> fields,
  ) async {
    final result = <String, ExtractedValue>{};

    for (final entry in fields.entries) {
      result[entry.key] = await extractField(rowElement, entry.value);
    }

    return result;
  }

  /// 从 `Map<String, dynamic>` 配置批量构造 FieldConfig
  static Map<String, FieldConfig> parseFieldConfigs(
    Map<String, dynamic>? fieldsConfig,
  ) {
    if (fieldsConfig == null) return {};

    final result = <String, FieldConfig>{};
    for (final entry in fieldsConfig.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = FieldConfig.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return result;
  }

  /// 查找行元素列表
  List<dynamic> findRows(dynamic soup, String rowSelector) {
    return findElementBySelector(soup, rowSelector);
  }

  /// 查找第一个匹配元素
  dynamic findFirst(dynamic soup, String selector) {
    return findFirstElementBySelector(soup, selector);
  }
}
