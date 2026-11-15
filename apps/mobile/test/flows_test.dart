import 'test_catalog.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'booking validates contact, checks a real slot, requires consent, creates and cancels',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ClubRepository(persist: false);
      await repo.load();
      await tester.pumpWidget(
        OpenNIApp(repository: repo, initialScreen: 'booking'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对预约'));
      await tester.pumpAndSettle();
      expect(find.text('请填写至少 3 个字符的联系方式'), findsOneWidget);
      expect(repo.orders, isEmpty);
      await tester.ensureVisible(find.text('选择意向队友'));
      await tester.tap(find.text('选择意向队友'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阿屿').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('20:00'));
      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, 'demo-contact');
      await tester.tap(find.text('核对预约'));
      await tester.pumpAndSettle();
      expect(find.text('核对这次预约'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('三角洲 · PC 小时陪')).dy,
        greaterThanOrEqualTo(0),
      );
      await tester.tap(find.text('提交预约'));
      await tester.pumpAndSettle();
      expect(repo.orders, isEmpty);
      expect(find.text('请先阅读并同意预约说明'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交预约'));
      await tester.pumpAndSettle();
      expect(repo.orders, hasLength(1));
      expect(repo.orders.first['fulfillmentStatus'], 'awaiting_assignment');
      expect(find.text('订单详情'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('取消预约'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('取消预约'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      expect(repo.orders.first['status'], 'cancelled');
      expect(repo.orders.first['fulfillmentStatus'], 'cancelled');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('预约已取消'), findsWidgets);
    },
  );
  testWidgets('catalog filters have real empty and matching states', (
    tester,
  ) async {
    final repo = ClubRepository(persist: false);
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'services'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '复盘');
    await tester.pumpAndSettle();
    expect(find.text('三角洲 · 对局复盘'), findsOneWidget);
    expect(find.text('三角洲 · PC 小时陪'), findsNothing);
  });
  test('local demo idempotency and storage survive reloading', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = ClubRepository();
    await repo.load();
    final first = await repo.book(
      service: repo.services.first,
      variantId: 'pc-60',
      date: DateTime(2030, 1, 1),
      contact: 'demo',
      note: '',
      idempotencyKey: 'once',
    );
    final repeat = await repo.book(
      service: repo.services.first,
      variantId: 'pc-60',
      date: DateTime(2030, 1, 1),
      contact: 'demo',
      note: '',
      idempotencyKey: 'once',
    );
    expect(first['id'], repeat['id']);
    expect(repo.orders.length, 1);
    final restored = ClubRepository();
    await restored.load();
    expect(restored.orders.first['id'], first['id']);
    await restored.cancel(restored.orders.first);
    expect(restored.orders.first['status'], 'cancelled');
  });
  test(
    'remote booking sends no client price and uses authenticated token',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/auth/demo')) {
          return http.Response(
            jsonEncode({
              'token': 'test-session',
              'user': {'id': 'u1', 'name': 'Demo'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'id': 'o1', 'status': 'pending', 'priceCents': 6800}),
          201,
        );
      });
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        persist: false,
        client: client,
      );
      await repo.book(
        service: {...await catalogService(repo), 'priceCents': 1},
        variantId: 'pc-60',
        date: DateTime(2030),
        contact: 'demo',
        note: '',
        idempotencyKey: 'one',
      );
      final body = jsonDecode(requests.last.body) as Map;
      expect(body.containsKey('priceCents'), isFalse);
      expect(requests.last.headers['Authorization'], 'Bearer test-session');
      expect(repo.orders.first['priceCents'], 6800);
    },
  );
  test('remote outage never falls back to fictional catalog', () async {
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient(
        (_) async => http.Response('{"error":{"message":"Unavailable"}}', 503),
      ),
    );
    await repo.load();
    expect(repo.error, 'Unavailable');
    expect(repo.services, isEmpty);
    expect(repo.players, isEmpty);
  });
  test('production auth rejection prevents order creation', () async {
    var ordersCalled = false;
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/orders')) ordersCalled = true;
        return http.Response(
          '{"error":{"message":"Demo authentication disabled"}}',
          403,
        );
      }),
    );
    await expectLater(
      repo.book(
        service: await catalogService(repo),
        variantId: 'pc-60',
        date: DateTime(2030),
        contact: 'demo',
        note: '',
        idempotencyKey: 'blocked',
      ),
      throwsException,
    );
    expect(ordersCalled, isFalse);
    expect(repo.orders, isEmpty);
  });
}
