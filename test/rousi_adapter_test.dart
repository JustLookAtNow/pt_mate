import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/models/purchase_models.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/api/rousi_adapter.dart';

/// 记录请求并按需返回响应的假适配器，避免测试触达真实网络。
class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _errorResponse(int statusCode, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late SiteConfig config;

  setUp(() {
    config = const SiteConfig(
      id: 'rousipro',
      name: '肉丝Pro',
      baseUrl: 'https://rousi.pro/',
      siteType: SiteType.rousi,
      apiKey: 'pgk_test_key',
    );
  });

  RousiAdapter buildAdapter(_FakeHttpClientAdapter fake) {
    final dio = Dio();
    dio.httpClientAdapter = fake;
    final adapter = RousiAdapter(dio: dio);
    return adapter;
  }

  Future<RousiAdapter> initAdapter(_FakeHttpClientAdapter fake) async {
    final adapter = buildAdapter(fake);
    await adapter.init(config);
    return adapter;
  }

  group('列表解析', () {
    test('is_active=false 的免费促销回落为普通', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'torrents': [
              {
                'id': 9830,
                'uuid': '9830',
                'title': 'Expired Free Torrent',
                'size': 1024,
                'seeders': 1,
                'leechers': 0,
                'created_at': '2026-08-27T00:00:00Z',
                'promotion': {
                  'type': 2,
                  'is_active': false,
                  'until': '2026-08-01T00:00:00Z',
                },
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 20,
            'total_pages': 1,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      final result = await adapter.searchTorrents(keyword: 'movie');

      expect(result.items.single.discount, DiscountType.normal);
    });

    test('is_active=true 的免费促销生效', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'torrents': [
              {
                'id': 9831,
                'uuid': '9831',
                'title': 'Active Free Torrent',
                'size': 1024,
                'seeders': 1,
                'leechers': 0,
                'created_at': '2026-08-27T00:00:00Z',
                'promotion': {'type': 2, 'is_active': true},
              },
            ],
            'total': 1,
            'page': 1,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      final result = await adapter.searchTorrents();

      expect(result.items.single.discount, DiscountType.free);
    });

    test('种子标识优先使用数字 id 而不是 uuid', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'torrents': [
              {
                'id': 9832,
                'uuid': '9832',
                'title': 'Numeric Id Torrent',
                'size': 1024,
                'seeders': 0,
                'leechers': 0,
                'created_at': '2026-08-27T00:00:00Z',
              },
            ],
            'total': 1,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      final result = await adapter.searchTorrents();

      expect(result.items.single.id, '9832');
    });
  });

  group('下载链接与付费保护', () {
    test('付费未购买时抛出 SitePurchaseRequiredException', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'id': 9830,
            'title': 'Paid Torrent',
            'download_url': '',
            'price': 100,
            'is_purchased': false,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      await expectLater(
        adapter.genDlToken(id: '9830'),
        throwsA(isA<SitePurchaseRequiredException>()),
      );
    });

    test('已购买时返回 download_url', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'id': 9830,
            'title': 'Paid Torrent',
            'download_url': 'https://rousi.pro/dl/9830?capability=abc',
            'price': 100,
            'is_purchased': true,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      final url = await adapter.genDlToken(id: '9830');

      expect(url, 'https://rousi.pro/dl/9830?capability=abc');
    });

    test('详情解析携带价格与购买状态', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'id': 9830,
            'description': '## 简介',
            'price': 250,
            'is_purchased': true,
          },
        }),
      );
      final adapter = await initAdapter(fake);

      final detail = await adapter.fetchTorrentDetail('9830');

      expect(detail.price, 250);
      expect(detail.isPurchased, isTrue);
    });
  });

  group('购买状态', () {
    test('解析购买状态字段', () async {
      final fake = _FakeHttpClientAdapter((options) {
        expect(options.path, '/api/v1/torrents/9830/purchase');
        expect(options.headers['Authorization'], 'Bearer pgk_test_key');
        return _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'torrent_id': 9830,
            'title': 'Example Movie',
            'price': 100,
            'tax': 10,
            'seller_income': 90,
            'magic_balance': 500,
            'state': 'purchase_required',
            'is_purchased': false,
            'purchased_at': null,
            'legacy_import': false,
          },
        });
      });
      final adapter = await initAdapter(fake);

      final status = await adapter.fetchPurchaseStatus('9830');

      expect(status.price, 100);
      expect(status.tax, 10);
      expect(status.sellerIncome, 90);
      expect(status.magicBalance, 500);
      expect(status.state, PurchaseState.purchaseRequired);
      expect(status.requiresPurchase, isTrue);
      expect(status.hasEnoughBalance, isTrue);
    });

    test('HTTP 403 映射为权限不足而不是登录失效', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _errorResponse(403, {'code': 403, 'message': 'scope 不足'}),
      );
      final adapter = await initAdapter(fake);

      await expectLater(
        adapter.fetchPurchaseStatus('9830'),
        throwsA(
          isA<SitePurchaseException>().having(
            (e) => e.reason,
            'reason',
            PurchaseFailureReason.forbidden,
          ),
        ),
      );
    });
  });

  group('购买提交', () {
    test('提交 expected_price 并携带合法 UUID 幂等键', () async {
      final fake = _FakeHttpClientAdapter((options) {
        expect(options.method, 'POST');
        expect(options.path, '/api/v1/torrents/9830/purchase');
        expect(options.headers['Authorization'], 'Bearer pgk_test_key');

        final key = options.headers['Idempotency-Key']?.toString() ?? '';
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(key),
          isTrue,
          reason: '幂等键必须是 UUID，实际为 $key',
        );

        final body = options.data as Map<String, dynamic>;
        expect(body['expected_price'], 100);

        return _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'request_id': key,
            'torrent_id': 9830,
            'price': 100,
            'tax': 10,
            'seller_income': 90,
            'balance_after': 400,
            'purchased_at': '2026-08-27T12:00:00Z',
            'replayed': false,
          },
        });
      });
      final adapter = await initAdapter(fake);

      final result = await adapter.purchaseTorrent('9830', expectedPrice: 100);

      expect(result.price, 100);
      expect(result.balanceAfter, 400);
      expect(result.torrentId, 9830);
      expect(result.replayed, isFalse);
    });

    test('超时重试复用同一个幂等键', () async {
      var attempt = 0;
      final fake = _FakeHttpClientAdapter((options) {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'request_id': options.headers['Idempotency-Key'],
            'torrent_id': 9830,
            'price': 100,
            'balance_after': 400,
            'replayed': true,
          },
        });
      });
      final adapter = await initAdapter(fake);

      await adapter.purchaseTorrent('9830', expectedPrice: 100);

      expect(fake.requests.length, 2, reason: '超时应重试一次');
      final firstKey = fake.requests.first.headers['Idempotency-Key'];
      final secondKey = fake.requests.last.headers['Idempotency-Key'];
      expect(firstKey, isNotNull);
      expect(secondKey, firstKey, reason: '重试必须复用幂等键');
    });

    test('HTTP 402 映射为余额不足', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _errorResponse(402, {'code': 402, 'message': '魔力值不足'}),
      );
      final adapter = await initAdapter(fake);

      await expectLater(
        adapter.purchaseTorrent('9830', expectedPrice: 100),
        throwsA(
          isA<SitePurchaseException>().having(
            (e) => e.reason,
            'reason',
            PurchaseFailureReason.insufficientBalance,
          ),
        ),
      );
    });

    test('HTTP 409 映射为价格变化', () async {
      final fake = _FakeHttpClientAdapter(
        (_) => _errorResponse(409, {'code': 409, 'message': '种子价格已变化'}),
      );
      final adapter = await initAdapter(fake);

      await expectLater(
        adapter.purchaseTorrent('9830', expectedPrice: 100),
        throwsA(
          isA<SitePurchaseException>()
              .having(
                (e) => e.reason,
                'reason',
                PurchaseFailureReason.priceChanged,
              )
              .having((e) => e.message, 'message', '种子价格已变化'),
        ),
      );
    });
  });

  group('购买记录', () {
    test('解析分页与记录字段', () async {
      final fake = _FakeHttpClientAdapter((options) {
        expect(options.path, '/api/v1/purchases');
        expect(options.queryParameters['page'], 2);
        expect(options.queryParameters['page_size'], 50);
        return _jsonResponse({
          'code': 0,
          'message': 'success',
          'data': {
            'purchases': [
              {
                'torrent_id': 9830,
                'title': 'Example Movie',
                'category_name': '电影',
                'torrent_state': 'published',
                'price': 100,
                'purchased_at': '2026-08-27T12:00:00Z',
                'legacy_import': false,
              },
            ],
            'total': 1,
            'page': 2,
            'page_size': 50,
            'total_pages': 1,
          },
        });
      });
      final adapter = await initAdapter(fake);

      final history = await adapter.fetchPurchaseHistory(
        pageNumber: 2,
        pageSize: 50,
      );

      expect(history.records.single.torrentId, 9830);
      expect(history.records.single.price, 100);
      expect(history.records.single.categoryName, '电影');
      expect(history.page, 2);
      expect(history.pageSize, 50);
      expect(history.total, 1);
    });
  });
}
