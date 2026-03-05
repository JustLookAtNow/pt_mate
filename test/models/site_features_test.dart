import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';

void main() {
  group('SiteFeatures', () {
    test('fromJson 应兼容 torrentBrowse 与 supportTorrentBrowse', () {
      final fromTemplate = SiteFeatures.fromJson({'torrentBrowse': false});
      expect(fromTemplate.supportTorrentBrowse, isFalse);

      final fromStorage = SiteFeatures.fromJson({
        'supportTorrentBrowse': false,
      });
      expect(fromStorage.supportTorrentBrowse, isFalse);
    });

    test('缺省时 supportTorrentBrowse 默认为 true', () {
      final features = SiteFeatures.fromJson({});
      expect(features.supportTorrentBrowse, isTrue);
      expect(features.toJson()['supportTorrentBrowse'], isTrue);
    });
  });
}
