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

  group('Jpopsuki Web preset', () {
    test('加载通用 Web 模板、分类和分组解析规则', () async {
      final templates = await SiteConfigService.loadPresetSiteTemplates();
      final template = templates.firstWhere((item) => item.id == 'jpopsuki');

      expect(template.siteType, SiteType.web);
      expect(template.baseUrls, contains('https://jpopsuki.eu/'));
      expect(template.operationIntervalMs, 1000);
      expect(template.toSiteConfig().operationIntervalMs, 1000);
      expect(template.searchCategories, hasLength(11));
      expect(
        template.searchCategories.map((item) => item.displayName),
        orderedEquals(const <String>[
          'All',
          'Album',
          'Single',
          'PV',
          'DVD',
          'TV-Music',
          'TV-Variety',
          'TV-Drama',
          'Fansubs',
          'Pictures',
          'Misc',
        ]),
      );
      expect(
        template.searchCategories.map((item) {
          final parameters = item.parseParameters();
          return parameters.isEmpty
              ? null
              : '${parameters.keys.single}=${parameters.values.single}';
        }).toList(),
        orderedEquals(<String?>[
          null,
          'filter_cat[1]=1',
          'filter_cat[2]=1',
          'filter_cat[3]=1',
          'filter_cat[4]=1',
          'filter_cat[5]=1',
          'filter_cat[6]=1',
          'filter_cat[7]=1',
          'filter_cat[8]=1',
          'filter_cat[9]=1',
          'filter_cat[10]=1',
        ]),
      );
      expect(template.searchCategories.first.id, 'all');
      expect(template.searchCategories.first.parseParameters(), isEmpty);

      expect(template.features.supportMemberProfile, isTrue);
      expect(template.features.supportTorrentSearch, isTrue);
      expect(template.features.supportTorrentBrowse, isTrue);
      expect(template.features.supportTorrentDetail, isTrue);
      expect(template.features.supportDownload, isTrue);
      expect(template.features.supportCollection, isFalse);
      expect(template.features.supportHistory, isFalse);
      expect(template.features.supportAdvancedSearch, isFalse);
      expect(template.features.showCover, isTrue);

      final infoFinder = template.infoFinder!;
      final userInfo = infoFinder['userInfo'] as Map<String, dynamic>;
      final steps = userInfo['steps'] as List<dynamic>;
      final search = infoFinder['search'] as Map<String, dynamic>;
      final request = template.request!['search'] as Map<String, dynamic>;

      expect(steps, hasLength(2));
      expect((steps[0] as Map<String, dynamic>)['path'], '/index.php');
      final firstStepFields =
          (steps[0] as Map<String, dynamic>)['fields'] as Map<String, dynamic>;
      expect(
        (firstStepFields['userId'] as Map<String, dynamic>)['required'],
        isTrue,
      );
      expect(
        (steps[1] as Map<String, dynamic>)['path'],
        '/user.php?id={userId}',
      );
      expect(search['parser'], 'gazelleGrouped');
      expect(search['childColumnOffset'], 3);
      expect(search['childFields'], isA<Map<String, dynamic>>());
      expect(search['standaloneFields'], isA<Map<String, dynamic>>());
      expect(request['path'], '/torrents.php');
      expect(
        (request['params'] as Map<String, dynamic>)['searchstr'],
        '{keyword}',
      );
    });
  });
}
