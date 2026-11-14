import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/accessibility.dart';
import 'package:openni_club/booking.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('120 minute variant uses canonical total and rejects missing or unknown SKU', () async {
    final repo = ClubRepository(persist: false);
    await repo.load();
    Future<Json> book(String? variant) => repo.book(
      service: {...repo.services.first, 'priceCents': 1},
      variantId: variant,
      date: DateTime(2030),
      contact: 'demo',
      note: '',
      idempotencyKey: 'variant-$variant',
    );
    await expectLater(book(null), throwsException);
    await expectLater(book('unknown'), throwsException);
    expect(repo.orders, isEmpty);
    final order = await book('pc-120');
    expect(order['priceCents'], 7200);
    expect(order['durationMinutes'], 120);
    expect(order['serviceSnapshot']['variantId'], 'pc-120');
    expect(order['serviceSnapshot']['maps'], contains('零号大坝'));
    expect(order['fulfillmentStatus'], 'awaiting_assignment');
  });
  test(
    'remote SKU booking sends IDs only and preserves authoritative response',
    () async {
      late Json body;
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        persist: false,
        client: MockClient((r) async {
          expect(r.url.path, endsWith('/orders'));
          body = Json.from(jsonDecode(r.body));
          return http.Response(
            jsonEncode({
              'id': 'order',
              'variantId': 'pc-120',
              'priceCents': 7200,
              'durationMinutes': 120,
              'fulfillmentStatus': 'awaiting_assignment',
            }),
            201,
          );
        }),
      )..token = 'customer';
      final result = await repo.book(
        service: {...demoServices.first, 'priceCents': 1},
        variantId: 'pc-120',
        date: DateTime(2030),
        contact: 'demo',
        note: '',
        idempotencyKey: 'remote-120',
      );
      expect(body['variantId'], 'pc-120');
      expect(body.containsKey('priceCents'), isFalse);
      expect(body.containsKey('durationMinutes'), isFalse);
      expect(result['priceCents'], 7200);
    },
  );
  test('demo role switch retains token and customer orders, and production forbids it', () async {
    final requests = <http.Request>[];
    final repo =
        ClubRepository(
            baseUrl: 'https://club.example/api/v1',
            persist: false,
            client: MockClient((r) async {
              requests.add(r);
              return http.Response(
                jsonEncode({
                  'user': {'id': 'u1', 'name': 'Member'},
                  'role': 'member',
                  'playerId': 'p1',
                  'demo': true,
                }),
                200,
              );
            }),
          )
          ..token = 'same-session'
          ..orders = [
            {'id': 'existing'},
          ];
    await repo.switchDemoRole('member', playerId: 'p1');
    expect(requests.first.url.path, endsWith('/auth/demo/role'));
    expect(
      requests.every(
        (r) => r.headers['Authorization'] == 'Bearer same-session',
      ),
      isTrue,
    );
    expect(repo.token, 'same-session');
    expect(repo.orders.single['id'], 'existing');
    expect(repo.memberPlayerId, 'p1');
    final production = ClubRepository(appMode: 'production', persist: false);
    await expectLater(
      production.switchDemoRole('member', playerId: 'p1'),
      throwsException,
    );
  });
  test('member failures never mutate local order or ledger into success', () async {
    final repo =
        ClubRepository(
            baseUrl: 'https://club.example/api/v1',
            persist: false,
            client: MockClient(
              (r) async => http.Response(
                '{"error":{"message":"Order is not assigned to this member"}}',
                403,
              ),
            ),
          )
          ..token = 'member'
          ..role = 'member';
    final order = <String, dynamic>{
      'id': 'foreign',
      'fulfillmentStatus': 'awaiting_acceptance',
    };
    await expectLater(repo.memberAction(order, 'accept'), throwsException);
    expect(order['fulfillmentStatus'], 'awaiting_acceptance');
    expect(repo.earnings, isEmpty);
    final local = ClubRepository(persist: false);
    await local.loadMemberData();
    final original = jsonEncode(local.memberOrders);
    await expectLater(
      local.memberAction(local.memberOrders.first, 'accept'),
      throwsException,
    );
    await expectLater(local.setMemberAvailability([]), throwsException);
    expect(jsonEncode(local.memberOrders), original);
  });
  test(
    'Studio presentation overrides cannot change production or API authority',
    () {
      final repo = ClubRepository(persist: false);
      applyBrandPreview(
        repo,
        Uri.parse(
          'https://openni.im/demo/?previewName=NewClub&previewColor=%23AABBCC&previewLogo=blob:https://other.example/a&apiBaseUrl=https://evil.example&mode=production',
        ),
      );
      expect(repo.clubName, 'NewClub');
      expect(repo.club['primaryColor'], '#AABBCC');
      expect(repo.club.containsKey('previewLogoUrl'), isFalse);
      expect(repo.isProduction, isFalse);
      expect(repo.baseUrl, isEmpty);
      applyBrandPreview(
        repo,
        Uri.parse(
          'https://openni.im/demo/?previewLogo=blob:https://openni.im/allowed',
        ),
      );
      expect(repo.club['previewLogoUrl'], 'blob:https://openni.im/allowed');
      final production = ClubRepository(appMode: 'production', persist: false);
      final before = Json.from(production.club);
      applyBrandPreview(
        production,
        Uri.parse(
          'https://openni.im/demo/?previewName=Override&previewColor=%23000000',
        ),
      );
      expect(production.club, before);
    },
  );
  testWidgets('selected 120 minute variant reaches the booking page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ClubRepository(persist: false);
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'service'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC · 120分钟'));
    await tester.pumpAndSettle();
    expect(find.text('¥72/套餐', findRichText: true), findsOneWidget);
    await tester.tap(find.text('立即预约'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookingPage>(find.byType(BookingPage)).variantId,
      'pc-120',
    );
    expect(find.text('¥72'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('glass respects Reduce Transparency and high contrast', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      GlassPreferences.reduceTransparency.value = false;
    });
    Widget app({bool highContrast = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: const GlassSurface(child: SizedBox(width: 100, height: 100)),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.byType(BackdropFilter), findsOneWidget);
    GlassPreferences.reduceTransparency.value = true;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    GlassPreferences.reduceTransparency.value = false;
    await tester.pumpWidget(app(highContrast: true));
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
