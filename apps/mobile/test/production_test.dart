import 'test_catalog.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/wechat_gateway.dart';

class FakeWechat implements WechatGateway {
  @override
  String? unavailableReason;
  int logins = 0, payments = 0;
  bool cancelPayment = false;
  @override
  Future<String> authenticate() async {
    logins++;
    return 'native-oauth-code';
  }

  @override
  Future<void> pay(Map<String, dynamic> parameters) async {
    payments++;
    if (cancelPayment) throw Exception('已取消微信操作。');
  }
}

const productionClub = <String, dynamic>{
  'demoData': false,
  'privacyText': 'Privacy policy',
  'termsText': 'Service terms',
  'supportContact': 'support@example.test',
};

void main() {
  test(
    'missing operating policies blocks native login before SDK access',
    () async {
      final sdk = FakeWechat();
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        appMode: 'production',
        persist: false,
        wechat: sdk,
      );
      expect(repo.authenticationUnavailable, contains('隐私'));
      await expectLater(repo.signIn(), throwsException);
      expect(sdk.logins, 0);
      repo.club = {...productionClub};
      expect(repo.authenticationUnavailable, isNull);
    },
  );
  test('production requires HTTPS and refuses seeded catalog', () async {
    for (final base in ['', 'http://club.example/api/v1']) {
      final repo = ClubRepository(
        baseUrl: base,
        appMode: 'production',
        persist: false,
      );
      await repo.load();
      expect(repo.error, contains('HTTPS'));
      expect(repo.services, isEmpty);
    }
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      appMode: 'production',
      persist: false,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(r.url.path.endsWith('/club') ? {'demoData': true} : []),
          200,
        ),
      ),
    );
    await repo.load();
    expect(repo.error, contains('演示资料'));
    expect(repo.services, isEmpty);
  });

  test('native auth exchanges code, never requests demo auth or sends client price', () async {
    final sdk = FakeWechat();
    final requests = <http.Request>[];
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      appMode: 'production',
      persist: false,
      wechat: sdk,
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/auth/wechat-app')
                ? {'token': 'real-session'}
                : {'id': 'o1', 'priceCents': 6800, 'status': 'pending'},
          ),
          200,
        );
      }),
    );
    repo.club = {...productionClub};
    await repo.book(
      service: {...await catalogService(repo), 'priceCents': 1},
      variantId: 'pc-60',
      date: DateTime(2030),
      contact: 'contact',
      note: '',
      idempotencyKey: 'unique',
    );
    expect(sdk.logins, 1);
    expect(requests.first.url.path, endsWith('/auth/wechat-app'));
    expect(jsonDecode(requests.first.body), {'code': 'native-oauth-code'});
    expect(requests.last.headers['Authorization'], 'Bearer real-session');
    expect(jsonDecode(requests.last.body).containsKey('priceCents'), isFalse);
    expect(requests.any((r) => r.url.path.endsWith('/auth/demo')), isFalse);
  });

  test(
    'wallet success waits for server and cancellation still refreshes order',
    () async {
      final sdk = FakeWechat();
      var serverState = 'pending';
      var refreshes = 0;
      final order = <String, dynamic>{
        'id': 'o1',
        'status': 'pending',
        'priceCents': 6800,
        'paymentStatus': 'unpaid',
      };
      final repo =
          ClubRepository(
              baseUrl: 'https://club.example/api/v1',
              appMode: 'production',
              persist: false,
              wechat: sdk,
              client: MockClient((r) async {
                if (r.method == 'GET') {
                  refreshes++;
                  return http.Response(
                    jsonEncode({...order, 'paymentStatus': serverState}),
                    200,
                  );
                }
                return http.Response(
                  '{"paymentParams":{"prepayId":"server-signed"},"paymentStatus":"pending"}',
                  200,
                );
              }),
            )
            ..token = 'session'
            ..club = {...productionClub};
      await repo.pay(order);
      expect(sdk.payments, 1);
      expect(order['paymentStatus'], 'pending');
      expect(order['paymentStatus'], isNot('paid'));
      sdk.cancelPayment = true;
      await expectLater(repo.pay(order), throwsException);
      expect(refreshes, 2);
      expect(order['paymentStatus'], 'pending');
      serverState = 'paid';
      await repo.refreshOrder(order);
      expect(order['paymentStatus'], 'paid');
      await expectLater(repo.pay(order), throwsException);
      expect(sdk.payments, 2);
    },
  );

  test(
    'failed deletion keeps account; successful deletion erases local session',
    () async {
      var reject = true;
      final repo =
          ClubRepository(
              baseUrl: 'https://club.example/api/v1',
              appMode: 'production',
              persist: false,
              wechat: FakeWechat(),
              client: MockClient((r) async {
                expect(r.method, 'DELETE');
                expect(r.url.path, endsWith('/account'));
                return reject
                    ? http.Response(
                        '{"error":{"message":"Unfinished orders"}}',
                        409,
                      )
                    : http.Response('{"deleted":true}', 200);
              }),
            )
            ..token = 'session'
            ..orders = [
              {'id': 'o1'},
            ];
      await expectLater(repo.deleteAccount(), throwsException);
      expect(repo.token, 'session');
      expect(repo.orders, hasLength(1));
      reject = false;
      await repo.deleteAccount();
      expect(repo.token, isNull);
      expect(repo.orders, isEmpty);
    },
  );

  testWidgets('unavailable SDK clearly disables production booking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sdk = FakeWechat()..unavailableReason = '请在 iOS 或 Android App 内使用。';
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      appMode: 'production',
      persist: false,
      wechat: sdk,
    );
    await tester.runAsync(() => catalogService(repo));
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'booking'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('核对预约'));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '核对预约'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('请在 iOS 或 Android App 内使用。'), findsOneWidget);
    expect(sdk.logins, 0);
  });

  testWidgets('account deletion requires explicit second confirmation', (
    tester,
  ) async {
    final repo = ClubRepository(persist: false)
      ..orders = [
        {'id': 'o1'},
      ];
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'settings'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('清除本地数据'));
    await tester.tap(find.text('清除本地数据'));
    await tester.pumpAndSettle();
    expect(repo.orders, hasLength(1));
    await tester.tap(find.text('保留资料'));
    await tester.pumpAndSettle();
    expect(repo.orders, hasLength(1));
    await tester.tap(find.text('清除本地数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();
    expect(repo.orders, isEmpty);
  });
}
