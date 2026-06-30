import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';

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
  });
}
