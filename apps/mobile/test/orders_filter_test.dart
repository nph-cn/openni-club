import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

void main() {
  testWidgets(
    'order shortcuts show selection and explain empty filtered results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = ClubRepository(persist: false);
      await repo.load();
      repo.orders = [
        {
          'id': 'payment',
          'serviceTitle': '待付款服务',
          'fulfillmentStatus': 'awaiting_payment',
          'priceCents': 2900,
        },
        {
          'id': 'done',
          'serviceTitle': '已结束服务',
          'fulfillmentStatus': 'completed',
          'priceCents': 3900,
        },
      ];
      await tester.pumpWidget(
        OpenNIApp(repository: repo, initialScreen: 'orders'),
      );
      await tester.pumpAndSettle();

      expect(find.text('待付款服务'), findsOneWidget);
      expect(find.text('已结束服务'), findsNothing);
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('order-filter-待付款')))
            .properties
            .selected,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('order-filter-待付款')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('order-filter-待付款')))
            .properties
            .selected,
        isTrue,
      );
      expect(find.text('待付款服务'), findsOneWidget);
      expect(find.text('已结束服务'), findsNothing);

      await tester.tap(find.byKey(const Key('order-filter-待接单')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('order-filter-待接单')))
            .properties
            .selected,
        isTrue,
      );
      expect(find.text('暂无待接单订单'), findsOneWidget);
      expect(find.text('这里还没有预约'), findsNothing);
      expect(find.text('待付款服务'), findsNothing);

      await tester.tap(find.text('查看全部订单'));
      await tester.pumpAndSettle();
      expect(find.text('待付款服务'), findsOneWidget);
      expect(find.text('已结束服务'), findsOneWidget);
      expect(find.text('暂无待接单订单'), findsNothing);
    },
  );
}
