import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/site_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SiteConfigService.clearAllCache();
  });

  tearDown(() {
    SiteConfigService.clearAllCache();
  });

  group('SiteConfigService default fallback', () {
    test('缺失 discountMapping 时应回退为类型默认值', () async {
      final template = await SiteConfigService.getTemplateById(
        'ptzone',
        SiteType.nexusphp,
      );

      expect(template, isNotNull);
      expect(template!.discountMapping, isNotEmpty);
      expect(template.discountMapping.containsKey('Free'), isTrue);
    });
  });
}
