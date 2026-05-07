import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/html_extractor.dart';

void main() {
  group('FieldConfig', () {
    test('should create from JSON', () {
      final config = FieldConfig.fromJson({
        'selector': 'td.name',
        'attribute': 'text',
        'filter': {'name': 'regexp', 'args': r'\d+'},
      });

      expect(config.selector, 'td.name');
      expect(config.attribute, 'text');
      expect(config.filter, isNotNull);
      expect(config.filter?['name'], 'regexp');
      expect(config.required, false);
    });

    test('should handle missing fields', () {
      final config = FieldConfig.fromJson({});

      expect(config.selector, isNull);
      expect(config.attribute, isNull);
      expect(config.filter, isNull);
    });

    test('should convert to JSON', () {
      final config = FieldConfig(
        selector: 'a.link',
        attribute: 'href',
        filter: {'name': 'regexp', 'args': r'id=(\d+)'},
      );

      final json = config.toJson();
      expect(json['selector'], 'a.link');
      expect(json['attribute'], 'href');
      expect(json['filter'], isNotNull);
    });
  });

  group('ExtractedValue', () {
    test('should handle missing value', () {
      final value = ExtractedValue.missing();

      expect(value.found, false);
      expect(value.hasValue, false);
      expect(value.string, isNull);
      expect(value.stringOrEmpty, '');
      expect(value.intValue, isNull);
      expect(value.doubleValue, isNull);
      expect(value.asBool, false);
    });

    test('should handle empty string as missing', () {
      final value = ExtractedValue.fromString('');

      expect(value.found, false);
      expect(value.hasValue, false);
    });

    test('should parse string value', () {
      final value = ExtractedValue.fromString('hello');

      expect(value.found, true);
      expect(value.hasValue, true);
      expect(value.string, 'hello');
      expect(value.stringOrEmpty, 'hello');
    });

    test('should parse int value', () {
      final value = ExtractedValue.fromString('42');

      expect(value.intValue, 42);
      expect(value.intValueOr(0), 42);
    });

    test('should return default for missing int', () {
      final value = ExtractedValue.missing();

      expect(value.intValueOr(99), 99);
    });

    test('should parse double value', () {
      final value = ExtractedValue.fromString('3.14');

      expect(value.doubleValue, 3.14);
    });

    test('should parse double with comma', () {
      final value = ExtractedValue.fromString('1,234.56');

      expect(value.doubleValue, 1234.56);
    });

    test('should parse bool from found status', () {
      final found = ExtractedValue.fromString('anything');
      final missing = ExtractedValue.missing();

      expect(found.asBool, true);
      expect(missing.asBool, false);
    });

    test('should parse DateTime with format', () {
      final value = ExtractedValue.fromString('2024-03-15 14:30:00');
      final date = value.parseDateTime(
        format: 'yyyy-MM-dd HH:mm:ss',
        zone: '+08:00',
      );

      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 3);
      expect(date.day, 15);
    });

    test('should return null for missing DateTime', () {
      final value = ExtractedValue.missing();
      final date = value.parseDateTime();

      expect(date, isNull);
    });

    test('should return null for invalid DateTime', () {
      final value = ExtractedValue.fromString('not-a-date');
      final date = value.parseDateTime(fieldName: 'testField');

      expect(date, isNull);
    });
  });

  group('TypedConverter', () {
    group('parseSizeToBytes', () {
      test('should parse bytes', () {
        expect(TypedConverter.parseSizeToBytes('100 B'), 100);
      });

      test('should parse KB', () {
        expect(TypedConverter.parseSizeToBytes('1.5 KB'), 1536);
      });

      test('should parse KiB', () {
        expect(TypedConverter.parseSizeToBytes('2 KiB'), 2048);
      });

      test('should parse MB', () {
        expect(TypedConverter.parseSizeToBytes('1.5 MB'), 1572864);
      });

      test('should parse MiB', () {
        expect(TypedConverter.parseSizeToBytes('1 MiB'), 1048576);
      });

      test('should parse GB', () {
        expect(TypedConverter.parseSizeToBytes('2.5 GB'), 2684354560);
      });

      test('should parse GiB', () {
        expect(TypedConverter.parseSizeToBytes('1 GiB'), 1073741824);
      });

      test('should parse TB', () {
        expect(TypedConverter.parseSizeToBytes('1 TB'), 1099511627776);
      });

      test('should handle null', () {
        expect(TypedConverter.parseSizeToBytes(null), 0);
      });

      test('should handle empty string', () {
        expect(TypedConverter.parseSizeToBytes(''), 0);
      });

      test('should handle invalid format', () {
        expect(TypedConverter.parseSizeToBytes('unknown'), 0);
      });
    });

    group('parseDownloadStatus', () {
      test('should return none for null', () {
        expect(TypedConverter.parseDownloadStatus(null), DownloadStatus.none);
      });

      test('should return none for empty', () {
        expect(TypedConverter.parseDownloadStatus(''), DownloadStatus.none);
      });

      test('should return completed for 100', () {
        expect(
          TypedConverter.parseDownloadStatus('100'),
          DownloadStatus.completed,
        );
      });

      test('should return downloading for 50', () {
        expect(
          TypedConverter.parseDownloadStatus('50'),
          DownloadStatus.downloading,
        );
      });

      test('should return downloading for 0', () {
        expect(
          TypedConverter.parseDownloadStatus('0'),
          DownloadStatus.downloading,
        );
      });
    });

    group('parseDiscount', () {
      test('should return normal for null', () {
        expect(
          TypedConverter.parseDiscount(null, {}),
          DiscountType.normal,
        );
      });

      test('should return normal for empty mapping', () {
        expect(
          TypedConverter.parseDiscount('FREE', {}),
          DiscountType.normal,
        );
      });

      test('should parse mapped discount', () {
        final mapping = {'free_tag': 'FREE', '2x_tag': '2xFREE'};

        expect(
          TypedConverter.parseDiscount('free_tag', mapping),
          DiscountType.free,
        );
        expect(
          TypedConverter.parseDiscount('2x_tag', mapping),
          DiscountType.twoXFree,
        );
      });

      test('should return normal for unmapped value', () {
        final mapping = {'free_tag': 'FREE'};

        expect(
          TypedConverter.parseDiscount('unknown_tag', mapping),
          DiscountType.normal,
        );
      });
    });

    group('parseTagType', () {
      test('should return null for null', () {
        expect(TypedConverter.parseTagType(null, {}), isNull);
      });

      test('should parse mapped tag', () {
        final mapping = {'cn': 'chinese', 'official_tag': 'official'};

        expect(
          TypedConverter.parseTagType('cn', mapping),
          TagType.chinese,
        );
        expect(
          TypedConverter.parseTagType('official_tag', mapping),
          TagType.official,
        );
      });

      test('should return null for unmapped value', () {
        expect(TypedConverter.parseTagType('unknown', {}), isNull);
      });
    });

    group('parseTags', () {
      test('should match tags from text', () {
        final tags = TypedConverter.parseTags(
          'Movie 4K HDR x265',
          'Collection WEB-DL 1080p',
          [],
          {},
        );

        expect(tags.contains(TagType.fourK), true);
        expect(tags.contains(TagType.hdr), true);
        expect(tags.contains(TagType.h265), true);
        expect(tags.contains(TagType.webDl), true);
        expect(tags.contains(TagType.resolution1080), true);
      });

      test('should match tags case insensitively', () {
        final tags = TypedConverter.parseTags(
          'movie 4k hdr x265',
          'collection web-dl 1080p',
          [],
          {},
        );

        expect(tags.contains(TagType.fourK), true);
        expect(tags.contains(TagType.hdr), true);
        expect(tags.contains(TagType.h265), true);
        expect(tags.contains(TagType.webDl), true);
        expect(tags.contains(TagType.resolution1080), true);
      });

      test('should include mapped tags', () {
        final tags = TypedConverter.parseTags(
          'Movie',
          '',
          ['cn', 'official_tag'],
          {'cn': 'chinese', 'official_tag': 'official'},
        );

        expect(tags.contains(TagType.chinese), true);
        expect(tags.contains(TagType.official), true);
      });

      test('should not duplicate tags', () {
        final tags = TypedConverter.parseTags(
          'Movie 4K',
          '',
          ['4k_tag'],
          {'4k_tag': '4K'},
        );

        // 4K should appear only once even though matched both from text and mapping
        expect(tags.where((t) => t == TagType.fourK).length, 1);
      });
    });

    group('resolveUrl', () {
      test('should return empty for null', () {
        expect(TypedConverter.resolveUrl(null, 'https://example.com'), '');
      });

      test('should return absolute URL as-is', () {
        expect(
          TypedConverter.resolveUrl('https://cdn.example.com/img.jpg', 'https://example.com'),
          'https://cdn.example.com/img.jpg',
        );
      });

      test('should resolve relative URL with slash', () {
        expect(
          TypedConverter.resolveUrl('/pic/img.jpg', 'https://example.com'),
          'https://example.com/pic/img.jpg',
        );
      });

      test('should resolve relative URL without slash', () {
        expect(
          TypedConverter.resolveUrl('pic/img.jpg', 'https://example.com/'),
          'https://example.com/pic/img.jpg',
        );
      });

      test('should handle base URL without trailing slash', () {
        expect(
          TypedConverter.resolveUrl('pic/img.jpg', 'https://example.com'),
          'https://example.com/pic/img.jpg',
        );
      });
    });

    group('resolveDownloadUrl', () {
      test('should replace all placeholders', () {
        final url = TypedConverter.resolveDownloadUrl(
          '{baseUrl}/download.php?id={torrentId}&passkey={passKey}',
          '12345',
          'abc123',
          'https://pt.example.com',
        );

        expect(url, 'https://pt.example.com/download.php?id=12345&passkey=abc123');
      });

      test('should handle base URL with trailing slash', () {
        final url = TypedConverter.resolveDownloadUrl(
          '{baseUrl}/download.php?downhash={userId}.{passKey}',
          '999',
          'jwt_token',
          'https://example.com/',
          userId: '20148',
        );

        expect(url, 'https://example.com/download.php?downhash=20148.jwt_token');
      });
    });
  });

  group('HtmlExtractor.parseFieldConfigs', () {
    test('should parse fields from JSON config', () {
      final configs = HtmlExtractor.parseFieldConfigs({
        'torrentId': {
          'selector': 'a[href^="details.php?id="]',
          'attribute': 'href',
          'filter': {'name': 'regexp', 'args': r'id=(\d+)', 'value': r'$1'},
        },
        'torrentName': {
          'selector': 'a.title',
          'attribute': 'text',
        },
      });

      expect(configs.length, 2);
      expect(configs['torrentId']?.selector, 'a[href^="details.php?id="]');
      expect(configs['torrentId']?.attribute, 'href');
      expect(configs['torrentName']?.selector, 'a.title');
    });

    test('should return empty map for null', () {
      final configs = HtmlExtractor.parseFieldConfigs(null);

      expect(configs, isEmpty);
    });

    test('should skip non-map values', () {
      final configs = HtmlExtractor.parseFieldConfigs({
        'validField': {'selector': 'div'},
        'invalidField': 'not-a-map',
      });

      expect(configs.length, 1);
      expect(configs.containsKey('validField'), true);
    });
  });
}
