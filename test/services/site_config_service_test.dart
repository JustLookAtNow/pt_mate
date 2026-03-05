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
    test('缺失键应回退默认模板，显式空对象保持不变', () async {
      final template = await SiteConfigService.getTemplateById(
        'hdkyl',
        SiteType.nexusphpweb,
      );

      expect(template, isNotNull);
      expect(template!.request, isNotNull);
      expect(template.features.supportTorrentBrowse, isTrue);

      // hdkyl.json 显式配置为空对象，应保留为空而不是被默认模板覆盖
      expect(template.discountMapping, isEmpty);
      expect(template.tagMapping, isEmpty);
    });

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
