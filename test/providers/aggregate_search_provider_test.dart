import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';
import 'package:pt_mate/services/aggregate_search_service.dart';

void main() {
  group('AggregateSearchProvider', () {
    test('setSearchKeyword silently updates keyword when notify is false', () {
      final provider = AggregateSearchProvider();
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount++;
      });

      provider.setSearchKeyword('abc', notify: false);

      expect(provider.searchKeyword, 'abc');
      expect(notificationCount, 0);
    });

    test('setSearchKeyword notifies listeners by default', () {
      final provider = AggregateSearchProvider();
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount++;
      });

      provider.setSearchKeyword('abc');

      expect(provider.searchKeyword, 'abc');
      expect(notificationCount, 1);
    });

    test('setSearchKeyword skips notification for unchanged keyword', () {
      final provider = AggregateSearchProvider();
      provider.setSearchKeyword('abc', notify: false);
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount++;
      });

      provider.setSearchKeyword('abc');

      expect(provider.searchKeyword, 'abc');
      expect(notificationCount, 0);
    });

    test('mergeRetriedSearchResult preserves results and remaining errors', () {
      final provider = AggregateSearchProvider();
      provider.setSearchResults([
        _resultItem(siteId: 'site-a', torrentId: '1'),
      ]);
      provider.setSearchErrors({'site-b': '连接超时', 'site-c': '连接超时'});

      provider.mergeRetriedSearchResult(
        retriedSiteIds: {'site-b', 'site-c'},
        items: [_resultItem(siteId: 'site-b', torrentId: '2')],
        errors: {'site-c': '仍然超时'},
      );

      expect(provider.searchResults.map((item) => item.siteId), [
        'site-a',
        'site-b',
      ]);
      expect(provider.searchErrors, {'site-c': '仍然超时'});
    });

    test('mergeSearchResults appends results and replaces duplicates', () {
      final provider = AggregateSearchProvider();
      provider.setSearchResults([
        _resultItem(siteId: 'site-a', torrentId: '1', name: '旧标题'),
      ]);

      provider.mergeSearchResults([
        _resultItem(siteId: 'site-a', torrentId: '1', name: '新标题'),
        _resultItem(siteId: 'site-b', torrentId: '2'),
      ]);

      expect(provider.searchResults, hasLength(2));
      expect(provider.searchResults.first.torrent.name, '新标题');
      expect(provider.searchResults.last.siteId, 'site-b');
    });

    test('mergeSearchResults ignores an empty batch', () {
      final provider = AggregateSearchProvider();
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount++;
      });

      provider.mergeSearchResults(const []);

      expect(provider.searchResults, isEmpty);
      expect(notificationCount, 0);
    });

    test(
      'mergeRetriedSearchResult replaces duplicate site torrent results',
      () {
        final provider = AggregateSearchProvider();
        provider.setSearchResults([
          _resultItem(siteId: 'site-a', torrentId: '1', name: '旧标题'),
        ]);

        provider.mergeRetriedSearchResult(
          retriedSiteIds: {'site-a'},
          items: [_resultItem(siteId: 'site-a', torrentId: '1', name: '新标题')],
          errors: const {},
        );

        expect(provider.searchResults, hasLength(1));
        expect(provider.searchResults.single.torrent.name, '新标题');
      },
    );
  });
}

AggregateSearchResultItem _resultItem({
  required String siteId,
  required String torrentId,
  String name = '测试种子',
}) {
  return AggregateSearchResultItem(
    siteId: siteId,
    siteName: siteId,
    torrent: TorrentItem(
      id: torrentId,
      name: name,
      smallDescr: '',
      discountEndTime: null,
      downloadUrl: null,
      seeders: 0,
      leechers: 0,
      sizeBytes: 0,
      createdDate: DateTime(2026),
      imageList: const [],
      cover: '',
    ),
  );
}
