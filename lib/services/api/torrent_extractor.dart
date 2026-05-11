import '../../models/app_models.dart';
import 'html_extractor.dart';

/// 种子行提取器
/// 封装从单个 HTML 行元素提取 TorrentItem 的完整逻辑
class TorrentRowExtractor {
  final Map<String, dynamic> _rawFieldsConfig;
  final Map<String, FieldConfig> _fields;
  final Map<String, String> _discountMapping;
  final Map<String, String> _tagMapping;
  final String _userId;
  final HtmlExtractor _extractor = HtmlExtractor();

  TorrentRowExtractor({
    required Map<String, dynamic> fieldsConfig,
    required Map<String, String> discountMapping,
    required Map<String, String> tagMapping,
    String userId = '',
  }) : _rawFieldsConfig = fieldsConfig,
       _fields = HtmlExtractor.parseFieldConfigs(fieldsConfig),
       _discountMapping = discountMapping,
       _tagMapping = tagMapping,
       _userId = userId;

  /// 从行元素提取 TorrentItem
  /// 如果 torrentId 缺失或为空，返回 null（跳过当前行）
  TorrentItem? extract(
    dynamic rowElement, {
    required String baseUrl,
    required String passKey,
    List<String>? logs,
  }) {
    final extracted = _extractor.extractRowResultsSync(rowElement, _fields);

    // 提取种子ID - 必须字段，缺失则跳过
    final torrentId = extracted['torrentId']?.first.stringOrEmpty ?? '';
    if (torrentId.isEmpty) {
      logs?.add(
        'TorrentRowExtractor: 缺失 torrentId，跳过当前行。配置: ${_fields['torrentId']?.toJson()}',
      );
      return null;
    }

    // 提取基本字段
    final torrentName = extracted['torrentName']?.first.stringOrEmpty ?? '';
    final description = extracted['description']?.first.stringOrEmpty ?? '';
    final discountRaw = extracted['discount']?.first.stringOrEmpty ?? '';
    final discountEndTimeRaw =
        extracted['discountEndTime']?.first.stringOrEmpty ?? '';
    final sizeText = extracted['sizeText']?.first.stringOrEmpty ?? '';
    final downloadStatusText =
        extracted['downloadStatus']?.first.stringOrEmpty ?? '';
    final coverRaw = extracted['cover']?.first.stringOrEmpty ?? '';
    final doubanRating = extracted['doubanRating']?.first.stringOrEmpty ?? '';
    final imdbRating = extracted['imdbRating']?.first.stringOrEmpty ?? '';

    // 提取标签列表（原始字符串）
    final tagRawList = extracted['tag']?.allValues ?? const <String>[];

    // 解析下载链接
    var downloadUrl = '';
    final downloadUrlConfig = _fields['downloadUrl'];
    if (downloadUrlConfig != null && downloadUrlConfig.hasValue) {
      // 使用 value 模板生成下载链接
      downloadUrl = TypedConverter.resolveDownloadUrl(
        downloadUrlConfig.value!,
        torrentId,
        passKey,
        baseUrl,
        userId: _userId,
      );
    } else {
      // fallback: 尝试从 HTML selector 提取的值
      downloadUrl = extracted['downloadUrl']?.first.stringOrEmpty ?? '';
    }

    // 解析封面URL
    final cover = TypedConverter.resolveUrl(coverRaw, baseUrl);

    // 解析日期时间配置
    final discountEndTimeTimeConfig = _extractNestedConfig(
      'discountEndTime',
      'time',
    );
    final createDateTimeConfig = _extractNestedConfig('createDate', 'time');

    // 构建 TorrentItem
    return TorrentItem(
      id: torrentId,
      name: torrentName,
      smallDescr: description.trim(),
      discount: TypedConverter.parseDiscount(
        discountRaw.isNotEmpty ? discountRaw : null,
        _discountMapping,
      ),
      discountEndTime: discountEndTimeRaw.isNotEmpty
          ? extracted['discountEndTime']?.first.parseDateTime(
              format: discountEndTimeTimeConfig?['format'] as String?,
              zone: discountEndTimeTimeConfig?['zone'] as String?,
              fieldName: 'discountEndTime',
            )
          : null,
      downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
      seeders: extracted['seedersText']?.first.intValueOr(0) ?? 0,
      leechers: extracted['leechersText']?.first.intValueOr(0) ?? 0,
      sizeBytes: TypedConverter.parseSizeToBytes(sizeText),
      downloadStatus: TypedConverter.parseDownloadStatus(downloadStatusText),
      collection: extracted['collection']?.first.asBool ?? false,
      imageList: const [],
      cover: cover,
      createdDate:
          extracted['createDate']?.first.parseDateTime(
            format: createDateTimeConfig?['format'] as String?,
            zone: createDateTimeConfig?['zone'] as String?,
            fieldName: 'createdDate',
          ) ??
          DateTime.now(),
      doubanRating: doubanRating.isNotEmpty ? doubanRating : 'N/A',
      imdbRating: imdbRating.isNotEmpty ? imdbRating : 'N/A',
      isTop: extracted['isTop']?.first.asBool ?? false,
      tags: TypedConverter.parseTags(
        torrentName,
        description,
        tagRawList,
        _tagMapping,
      ),
      comments: extracted['comments']?.first.intValueOr(0) ?? 0,
    );
  }

  /// 提取嵌套配置，如 fieldsConfig['discountEndTime']['time']
  Map<String, dynamic>? _extractNestedConfig(
    String fieldName,
    String nestedKey,
  ) {
    final fieldConfig = _rawFieldsConfig[fieldName] as Map<String, dynamic>?;
    if (fieldConfig == null) return null;
    return fieldConfig[nestedKey] as Map<String, dynamic>?;
  }
}
