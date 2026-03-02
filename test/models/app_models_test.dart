import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';

void main() {
  group('AggregateSearchConfig', () {
    test('fromJson correctly parses new format (enabledSites)', () {
      final json = {
        'id': 'test-config',
        'name': 'Test Config',
        'type': 'custom',
        'isActive': true,
        'enabledSites': [
          {'id': 'site1', 'additionalParams': null},
          {'id': 'site2', 'additionalParams': {'key': 'value'}}
        ]
      };

      final config = AggregateSearchConfig.fromJson(json);

      expect(config.id, 'test-config');
      expect(config.name, 'Test Config');
      expect(config.type, 'custom');
      expect(config.isActive, true);
      expect(config.enabledSites.length, 2);
      expect(config.enabledSites[0].id, 'site1');
      expect(config.enabledSites[1].id, 'site2');
      expect(config.enabledSites[1].additionalParams, {'key': 'value'});
    });

    test('fromJson ignores old format (enabledSiteIds)', () {
      final json = {
        'id': 'legacy-config',
        'name': 'Legacy Config',
        'type': 'custom',
        'isActive': true,
        'enabledSiteIds': ['site1', 'site2']
      };

      final config = AggregateSearchConfig.fromJson(json);

      expect(config.id, 'legacy-config');
      expect(config.name, 'Legacy Config');
      // Should be empty since we removed the compatibility code
      expect(config.enabledSites, isEmpty);
    });
  });
}
