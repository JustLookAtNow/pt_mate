import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/unit3d_adapter.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';

void main() {
  group('Unit3dAdapter', () {
    late Unit3dAdapter adapter;
    late SiteConfig config;

    setUp(() {
      config = const SiteConfig(
        id: 'test_unit3d',
        name: 'Test Unit3d',
        baseUrl: 'https://test.unit3d.com',
        siteType: SiteType.unit3d,
        apiKey: 'test_api_key',
      );
      adapter = Unit3dAdapter();
      adapter.init(config);
    });

    test('config returns correctly', () {
      expect(adapter.siteConfig.id, 'test_unit3d');
      expect(adapter.siteConfig.apiKey, 'test_api_key');
    });

    // Would need dio mocking to test the actual API responses for search, profile, etc.
    // For now we just test that the adapter initializes correctly.
  });
}
