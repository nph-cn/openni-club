import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/booking.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

class ScheduleRepository extends ClubRepository {
  ScheduleRepository({required super.clock, this.rawSlots})
    : super(persist: false);
  final List<Json>? rawSlots;
  final dates = <DateTime>[];

  @override
  Future<List<Json>> getAvailability(
    String playerId,
    DateTime date,
    int duration,
  ) async {
    dates.add(date);
    return rawSlots ?? super.getAvailability(playerId, date, duration);
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> selectPlayer(WidgetTester tester) async {
  await tester.ensureVisible(find.text('选择意向队友'));
  await tester.tap(find.text('选择意向队友'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('阿屿').last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final topLevel in [false, true]) {
    testWidgets(topLevel ? '再次预约优先保留顶层规格' : 'API 订单从冻结快照恢复再次预约规格', (
      tester,
    ) async {
      phone(tester);
      final repo = ClubRepository(
        persist: false,
        clock: () => DateTime.utc(2026, 11, 16, 5),
      );
      await repo.load();
      // 采用 API 导出的完整订单结构；接口没有顶层 variantId。
      final order = Json.from(
        jsonDecode(
          await rootBundle.loadString(
            'assets/demo/order-in-progress.json',
            cache: false,
          ),
        ),
      );
      order.addAll({
        'status': 'completed',
        'fulfillmentStatus': 'completed',
        'serviceSnapshot': {
          ...Json.from(order['serviceSnapshot']),
          'variantId': 'pc-120',
          'durationMinutes': 120,
          'priceCents': 7200,
        },
      });
      if (topLevel) {
        order['variantId'] = 'pc-60';
      } else {
        order.remove('variantId');
      }
      repo.orders = [order];
      await tester.pumpWidget(
        OpenNIApp(repository: repo, initialScreen: 'order'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('再次预约'));
      await tester.pumpAndSettle();
      final booking = tester.widget<BookingPage>(find.byType(BookingPage));
      expect(booking.variantId, topLevel ? 'pc-60' : 'pc-120');
      expect(booking.playerId, order['assignedPlayerId']);
      expect(find.text(topLevel ? '¥39' : '¥72'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('默认今天并隐藏过期或不足一分钟的排班响应', (tester) async {
    phone(tester);
    final repo = ScheduleRepository(
      clock: () => DateTime.utc(2026, 11, 16, 8),
      rawSlots: [
        for (final start in [
          '2026-11-16T06:00:00Z',
          '2026-11-16T08:00:30Z',
          '2026-11-16T10:00:00Z',
        ])
          {'startAt': start, 'available': true},
      ],
    );
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'booking'),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('明天'), findsOneWidget);
    await selectPlayer(tester);
    expect(repo.dates.single, DateTime(2026, 11, 16));
    expect(find.text('14:00'), findsNothing);
    expect(find.text('16:00'), findsNothing);
    expect(find.text('18:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('今天没有余下排班时可以切换明天', (tester) async {
    phone(tester);
    final repo = ScheduleRepository(
      clock: () => DateTime.utc(2026, 11, 16, 13),
    );
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'booking'),
    );
    await tester.pumpAndSettle();
    await selectPlayer(tester);
    expect(find.text('这一天暂无可约时段，试试其他日期或队友。'), findsOneWidget);
    await tester.ensureVisible(find.text('明天'));
    await tester.tap(find.text('明天'));
    await tester.pumpAndSettle();
    expect(repo.dates.last, DateTime(2026, 11, 17));
    expect(find.text('14:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('核对后等待到时段过期不能提交旧排班', (tester) async {
    phone(tester);
    var now = DateTime.utc(2026, 11, 16, 5);
    final repo = ScheduleRepository(
      clock: () => now,
      rawSlots: [
        {'startAt': '2026-11-16T06:00:00Z', 'available': true},
      ],
    );
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'booking'),
    );
    await tester.pumpAndSettle();
    await selectPlayer(tester);
    await tester.ensureVisible(find.text('14:00'));
    await tester.tap(find.text('14:00'));
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, 'demo-contact');
    await tester.tap(find.text('核对预约'));
    await tester.pumpAndSettle();
    expect(find.text('核对这次预约'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    now = DateTime.utc(2026, 11, 16, 6);
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(repo.orders, isEmpty);
    expect(find.text('该时段已不可约，请返回重新选择。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
