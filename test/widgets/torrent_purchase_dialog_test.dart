import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/purchase_models.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/widgets/torrent_purchase_dialog.dart';

PurchaseStatus _status({
  int price = 100,
  int tax = 10,
  int sellerIncome = 90,
  int magicBalance = 500,
  PurchaseState state = PurchaseState.purchaseRequired,
  bool isPurchased = false,
}) => PurchaseStatus(
  torrentId: 9830,
  title: 'Example Movie',
  price: price,
  tax: tax,
  sellerIncome: sellerIncome,
  magicBalance: magicBalance,
  state: state,
  isPurchased: isPurchased,
);

/// 承载弹窗返回值的容器：`showDialog` 的 Future 只能在弹窗关闭后 await，
/// 因此先存起来，交互完成后再取。
class _Harness {
  Future<TorrentPurchaseOutcome?>? outcome;
}

void main() {
  /// 打开购买弹窗并等待状态加载完成
  Future<_Harness> openDialog(
    WidgetTester tester, {
    required PurchaseStatusLoader loadStatus,
    PurchaseSubmitter? submitPurchase,
  }) async {
    final harness = _Harness();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  harness.outcome = showDialog<TorrentPurchaseOutcome>(
                    context: context,
                    builder: (_) => TorrentPurchaseDialog(
                      torrentId: '9830',
                      torrentTitle: 'Example Movie',
                      loadStatus: loadStatus,
                      submitPurchase: submitPurchase,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('展示价格、税费与余额，取消返回 null', (tester) async {
    final harness = await openDialog(
      tester,
      loadStatus: (_) async => _status(),
    );

    expect(find.text('100 魔力值'), findsOneWidget);
    expect(find.text('10 魔力值'), findsOneWidget);
    expect(find.text('90 魔力值'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('确认购买（花费 100 魔力值）'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(TorrentPurchaseDialog), findsNothing);
    expect(await harness.outcome, isNull);
  });

  testWidgets('确认购买时按展示价格提交并返回可继续', (tester) async {
    int? submittedPrice;
    final harness = await openDialog(
      tester,
      loadStatus: (_) async => _status(),
      submitPurchase: (torrentId, expectedPrice) async {
        expect(torrentId, '9830');
        submittedPrice = expectedPrice;
        return const PurchaseResult(
          requestId: 'req-1',
          torrentId: 9830,
          price: 100,
          balanceAfter: 400,
        );
      },
    );

    await tester.tap(find.text('确认购买（花费 100 魔力值）'));
    await tester.pumpAndSettle();
    final outcome = await harness.outcome;

    expect(submittedPrice, 100, reason: '必须提交展示给用户的价格');
    expect(outcome?.canProceed, isTrue);
    expect(outcome?.purchase?.balanceAfter, 400);
    expect(find.byType(TorrentPurchaseDialog), findsNothing);
  });

  testWidgets('已购买的种子不显示购买按钮，可直接继续', (tester) async {
    var submitCalled = false;
    final harness = await openDialog(
      tester,
      loadStatus: (_) async =>
          _status(state: PurchaseState.purchased, isPurchased: true),
      submitPurchase: (torrentId, expectedPrice) async {
        submitCalled = true;
        return const PurchaseResult();
      },
    );

    expect(
      find.descendant(
        of: find.byType(TorrentPurchaseDialog),
        matching: find.byType(ElevatedButton),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('已购买'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    final outcome = await harness.outcome;

    expect(submitCalled, isFalse);
    expect(outcome?.canProceed, isTrue);
    expect(outcome?.purchase, isNull);
  });

  testWidgets('余额不足时禁用确认按钮', (tester) async {
    await openDialog(
      tester,
      loadStatus: (_) async => _status(magicBalance: 50),
    );

    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '确认购买（花费 100 魔力值）'),
    );
    expect(confirmButton.onPressed, isNull);
    expect(find.textContaining('余额不足'), findsOneWidget);
  });

  testWidgets('价格变化时提示并刷新最新状态', (tester) async {
    var loadCount = 0;
    await openDialog(
      tester,
      loadStatus: (_) async {
        loadCount++;
        return _status(price: loadCount == 1 ? 100 : 150);
      },
      submitPurchase: (torrentId, expectedPrice) async {
        throw const SitePurchaseException(
          reason: PurchaseFailureReason.priceChanged,
          message: '种子价格已变化，请重新确认后再购买',
          statusCode: 409,
        );
      },
    );

    await tester.tap(find.text('确认购买（花费 100 魔力值）'));
    await tester.pumpAndSettle();

    expect(find.text('种子价格已变化，请重新确认后再购买'), findsOneWidget);
    expect(loadCount, 2, reason: '价格冲突后应重新拉取最新状态');
    expect(find.text('确认购买（花费 150 魔力值）'), findsOneWidget);
  });

  testWidgets('缺少购买 scope 时给出可操作提示', (tester) async {
    await openDialog(
      tester,
      loadStatus: (_) async => _status(),
      submitPurchase: (torrentId, expectedPrice) async {
        throw const SitePurchaseException(
          reason: PurchaseFailureReason.forbidden,
          message: 'forbidden',
          statusCode: 403,
        );
      },
    );

    await tester.tap(find.text('确认购买（花费 100 魔力值）'));
    await tester.pumpAndSettle();

    expect(find.textContaining('torrent:purchase:write'), findsOneWidget);
  });

  testWidgets('状态加载失败时保留网页端购买入口', (tester) async {
    await openDialog(
      tester,
      loadStatus: (_) async => throw SiteApiException(message: '该站点不支持应用内购买'),
    );

    expect(find.text('该站点不支持应用内购买'), findsOneWidget);
    expect(find.text('前往网页端购买'), findsOneWidget);
    expect(find.text('确认购买（花费 100 魔力值）'), findsNothing);
  });
}
