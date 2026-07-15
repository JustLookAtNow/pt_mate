// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/nexusphp_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('NexusPHPAdapter Tests', () {
    late NexusPHPAdapter adapter;

    setUp(() {
      adapter = NexusPHPAdapter();
    });

    test('getDownLoadHash should generate valid JWT token', () {
      // 测试数据
      const passkey = '6f7a9e699d6a62adedbd89f4d3f999a7';
      const id = '7836';
      const userid = '6349';

      // 直接调用公有方法
      final token = adapter.getDownLoadHash(passkey, id, userid);

      print('Generated JWT token: $token');

      // 验证返回的token不为空
      expect(token, isNotEmpty);

      // 验证token是有效的JWT格式（包含三个部分，用.分隔）
      final parts = token.split('.');
      expect(parts.length, equals(3));

      // 验证JWT内容
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final keyString = passkey + dateStr + userid;
      final keyBytes = utf8.encode(keyString);
      final digest = md5.convert(keyBytes);
      final key = digest.toString();

      try {
        final jwt = JWT.verify(token, SecretKey(key));
        final payload = jwt.payload as Map<String, dynamic>;

        // 验证payload内容
        expect(payload['id'], equals(id));
        expect(payload['exp'], isA<int>());

        // 验证过期时间（应该是当前时间+3600秒）
        final currentTime = (DateTime.now().millisecondsSinceEpoch / 1000)
            .floor();
        final expTime = payload['exp'] as int;
        expect(expTime, greaterThan(currentTime));
        expect(expTime, lessThanOrEqualTo(currentTime + 3600));
      } catch (e) {
        fail('JWT verification failed: $e');
      }
    });

    test(
      'getDownLoadHash should generate different tokens for different inputs',
      () {
        const passkey1 = 'passkey1';
        const passkey2 = 'passkey2';
        const id = '12345';
        const userid = '67890';

        final token1 = adapter.getDownLoadHash(passkey1, id, userid);
        final token2 = adapter.getDownLoadHash(passkey2, id, userid);

        print('Token for passkey1: $token1');
        print('Token for passkey2: $token2');

        // 不同的passkey应该生成不同的token
        expect(token1, isNot(equals(token2)));
      },
    );

    test(
      'getDownLoadHash should generate different tokens for different dates',
      () async {
        const passkey = 'test_passkey';
        const id = '12345';
        const userid = '67890';

        final token1 = adapter.getDownLoadHash(passkey, id, userid);

        // 等待一毫秒确保时间不同（虽然日期可能相同）
        await Future.delayed(const Duration(milliseconds: 1));

        final token2 = adapter.getDownLoadHash(passkey, id, userid);

        print('Token1: $token1');
        print('Token2: $token2');

        // 在同一天内，token应该相同（因为日期格式是Ymd）
        expect(token1, equals(token2));
      },
    );

    group('search category parameters', () {
      Future<({String path, Map<String, String> queryParameters})>
      performSearch(Map<String, dynamic>? additionalParams) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requestCompleter =
            Completer<({String path, Map<String, String> queryParameters})>();

        server.listen((request) async {
          requestCompleter.complete((
            path: request.uri.path,
            queryParameters: Map<String, String>.from(
              request.uri.queryParameters,
            ),
          ));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'ret': 0,
              'data': {
                'meta': {
                  'current_page': 1,
                  'per_page': 30,
                  'total': 0,
                  'last_page': 1,
                },
                'data': <Map<String, dynamic>>[],
              },
            }),
          );
          await request.response.close();
        });

        final searchAdapter = NexusPHPAdapter();
        await searchAdapter.init(
          SiteConfig(
            id: 'test-nexusphp',
            name: 'Test NexusPHP',
            baseUrl: 'http://${server.address.host}:${server.port}',
            siteType: SiteType.nexusphp,
            apiKey: 'test-api-key',
          ),
        );

        try {
          await searchAdapter.searchTorrents(
            additionalParams: additionalParams,
          );
          return await requestCompleter.future;
        } finally {
          await server.close(force: true);
        }
      }

      test('single segment category only appends section path', () async {
        final request = await performSearch({'category': 'movie'});

        expect(request.path, '/api/v1/torrents/movie');
        expect(request.queryParameters, isNot(contains('filter[category]')));
      });

      test(
        'two segment category appends section path and category filter',
        () async {
          final request = await performSearch({'category': 'movie#3'});

          expect(request.path, '/api/v1/torrents/movie');
          expect(request.queryParameters['filter[category]'], '3');
        },
      );

      test('missing category keeps the base torrents path', () async {
        final request = await performSearch(null);

        expect(request.path, '/api/v1/torrents');
        expect(request.queryParameters, isNot(contains('filter[category]')));
      });
    });
  });
}
