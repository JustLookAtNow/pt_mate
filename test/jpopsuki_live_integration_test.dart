import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/api/web_adapter.dart';
import 'package:pt_mate/services/site_config_service.dart';

const _cookieEnvironmentName = 'JPOPSUKI_COOKIE';

class _UnmockedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.idleTimeout = const Duration(seconds: 20);
    return client;
  }
}

class _ProbeSummary {
  final String label;
  final int? statusCode;
  final int? responseBytes;
  final int? candidateItemRows;
  final int? parsedItems;
  final int? resultItems;
  final int? totalPages;
  final int? itemsWithCover;
  final int? namesWithSeparator;
  final String? failure;

  const _ProbeSummary({
    required this.label,
    this.statusCode,
    this.responseBytes,
    this.candidateItemRows,
    this.parsedItems,
    this.resultItems,
    this.totalPages,
    this.itemsWithCover,
    this.namesWithSeparator,
    this.failure,
  });

  String toSafeLogLine() {
    return 'label=$label '
        'status=${statusCode ?? '-'} '
        'responseBytes=${responseBytes ?? 0} '
        'candidateRows=${candidateItemRows ?? 0} '
        'parsedItems=${parsedItems ?? 0} '
        'resultItems=${resultItems ?? 0} '
        'totalPages=${totalPages ?? 0} '
        'itemsWithCover=${itemsWithCover ?? 0} '
        'namesWithSeparator=${namesWithSeparator ?? 0} '
        'outcome=${failure ?? 'ok'}';
  }
}

Future<T> _withUnmockedHttp<T>(Future<T> Function() action) {
  return HttpOverrides.runZoned<Future<T>>(
    action,
    createHttpClient: _UnmockedHttpOverrides().createHttpClient,
  );
}

String _safeFailureSummary(Object error) {
  // 不调用 toString()，因为某些 HTTP 异常详情可能携带响应正文。
  if (error is SiteAuthenticationException) {
    return '${error.runtimeType}(status=${error.statusCode ?? '-'})';
  }
  if (error is SiteServiceException) {
    return '${error.runtimeType}(status=${error.statusCode ?? '-'})';
  }
  if (error is SiteException) return error.runtimeType.toString();
  return error.runtimeType.toString();
}

WebAdapterDiagnostic? _lastDiagnostic(
  List<WebAdapterDiagnostic> diagnostics,
  WebAdapterDiagnosticStage stage,
) {
  for (var index = diagnostics.length - 1; index >= 0; index--) {
    final diagnostic = diagnostics[index];
    if (diagnostic.stage == stage) return diagnostic;
  }
  return null;
}

Future<_ProbeSummary> _runSearchProbe({
  required String label,
  required SiteConfig config,
  required Map<String, dynamic> additionalParams,
}) async {
  final diagnostics = <WebAdapterDiagnostic>[];
  final adapter = WebAdapter(diagnosticSink: diagnostics.add);
  try {
    await adapter.init(config);
    final result = await adapter.searchTorrents(
      pageNumber: 1,
      pageSize: 30,
      additionalParams: additionalParams,
    );
    final request = _lastDiagnostic(
      diagnostics,
      WebAdapterDiagnosticStage.request,
    );
    final parse = _lastDiagnostic(
      diagnostics,
      WebAdapterDiagnosticStage.searchParse,
    );
    return _ProbeSummary(
      label: label,
      statusCode: request?.statusCode,
      responseBytes: request?.responseBytes,
      candidateItemRows: parse?.candidateItemRows,
      parsedItems: parse?.parsedItems,
      resultItems: result.items.length,
      totalPages: result.totalPages,
      itemsWithCover: result.items
          .where((item) => item.cover.isNotEmpty)
          .length,
      namesWithSeparator: result.items
          .where((item) => item.name.contains(' - '))
          .length,
    );
  } on Object catch (error) {
    final request = _lastDiagnostic(
      diagnostics,
      WebAdapterDiagnosticStage.request,
    );
    return _ProbeSummary(
      label: label,
      statusCode: request?.statusCode,
      responseBytes: request?.responseBytes,
      failure: _safeFailureSummary(error),
    );
  }
}

Future<void> _waitForOperationInterval(SiteConfig config) {
  return Future<void>.delayed(
    Duration(milliseconds: config.operationIntervalMs),
  );
}

/// 可选的 Jpopsuki 实网诊断。
///
/// 默认跳过。仅在当前进程显式提供 [JPOPSUKI_COOKIE] 时联网，不读取文件、
/// 不写入配置，也不会输出 Cookie、HTML、详情链接、下载链接或完整 URL query：
///
/// ```sh
/// read -rs JPOPSUKI_COOKIE
/// export JPOPSUKI_COOKIE
/// flutter test test/jpopsuki_live_integration_test.dart --reporter expanded
/// unset JPOPSUKI_COOKIE
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cookie = Platform.environment[_cookieEnvironmentName]?.trim();
  final enabled = cookie != null && cookie.isNotEmpty;

  test(
    'Jpopsuki 实网 Cookie 诊断（显式 opt-in）',
    () async {
      await _withUnmockedHttp(() async {
        final template = await SiteConfigService.getTemplateById(
          'jpopsuki',
          SiteType.web,
        );
        expect(template, isNotNull);
        final config = template!.toSiteConfig(cookie: cookie);

        final profileDiagnostics = <WebAdapterDiagnostic>[];
        final profileAdapter = WebAdapter(
          diagnosticSink: profileDiagnostics.add,
        );
        await profileAdapter.init(config);

        late MemberProfile profile;
        final stopwatch = Stopwatch()..start();
        try {
          profile = await profileAdapter.fetchMemberProfile();
        } on Object catch (error) {
          fail('Jpopsuki 实网资料请求失败: ${_safeFailureSummary(error)}');
        }

        await _waitForOperationInterval(config);
        final allProbe = await _runSearchProbe(
          label: 'all',
          config: config,
          additionalParams: const {},
        );
        await _waitForOperationInterval(config);
        final legacyCategoryProbe = await _runSearchProbe(
          label: 'legacy-filter_cat',
          config: config,
          additionalParams: const {'filter_cat': '1'},
        );
        await _waitForOperationInterval(config);
        final bracketCategoryProbe = await _runSearchProbe(
          label: 'bracket-filter_cat',
          config: config,
          additionalParams: const {'filter_cat[1]': '1'},
        );
        stopwatch.stop();

        final profileStatuses = profileDiagnostics
            .where(
              (diagnostic) =>
                  diagnostic.stage == WebAdapterDiagnosticStage.request,
            )
            .map((diagnostic) => diagnostic.statusCode ?? '-')
            .join(',');

        // 仅输出聚合统计，避免测试日志意外记录认证数据或页面内容。
        debugPrint(
          'Jpopsuki live diagnostic: '
          'profile=statuses=[$profileStatuses] '
          'userIdPresent=${profile.userId?.isNotEmpty == true} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        debugPrint('Jpopsuki live diagnostic: ${allProbe.toSafeLogLine()}');
        debugPrint(
          'Jpopsuki live diagnostic: ${legacyCategoryProbe.toSafeLogLine()}',
        );
        debugPrint(
          'Jpopsuki live diagnostic: ${bracketCategoryProbe.toSafeLogLine()}',
        );

        expect(profile.userId?.isNotEmpty, isTrue);
        expect(allProbe.failure, isNull);
        expect(allProbe.resultItems, greaterThan(0));
        expect(allProbe.itemsWithCover, greaterThan(0));
        expect(legacyCategoryProbe.failure, isNull);
        expect(bracketCategoryProbe.failure, isNull);
      });
    },
    skip: enabled ? false : '未设置 $_cookieEnvironmentName；实网诊断默认跳过。',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
