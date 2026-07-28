import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';

void main() {
  group('Web site type integration', () {
    test(
      'uses Cookie authentication but never enables Gazelle download token',
      () {
        expect(SiteType.web.usesCookieAuthentication, isTrue);
        expect(SiteType.web.supportsGazelleDownloadToken, isFalse);
        expect(SiteType.web.isAvailableForCustomSite, isFalse);
        expect(SiteType.gazelle.supportsGazelleDownloadToken, isTrue);
        expect(SiteType.gazelle.isAvailableForCustomSite, isTrue);
        expect(SiteType.nexusphp.usesCookieAuthentication, isFalse);
      },
    );

    test('serializes and restores the Web site type', () {
      const config = SiteConfig(
        id: 'web-site',
        name: 'Web Site',
        baseUrl: 'https://web.example/',
        cookie: 'session=abc',
        siteType: SiteType.web,
      );

      final restored = SiteConfig.fromJson(config.toJson());

      expect(restored.siteType, SiteType.web);
      expect(restored.cookie, 'session=abc');
    });

    test('TorrentItem.copyWith retains and updates detail URL', () {
      final item = TorrentItem(
        id: '1',
        name: 'Torrent',
        smallDescr: '',
        discountEndTime: null,
        downloadUrl: 'https://web.example/download/1',
        detailUrl: 'https://web.example/details/1',
        seeders: 1,
        leechers: 0,
        sizeBytes: 1024,
        createdDate: DateTime(2026, 7, 28),
        imageList: const [],
        cover: '',
      );

      expect(item.copyWith().detailUrl, item.detailUrl);
      expect(
        item.copyWith(detailUrl: 'https://web.example/details/2').detailUrl,
        'https://web.example/details/2',
      );
    });
  });
}
