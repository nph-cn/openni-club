import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/auth.dart';
import 'package:openni_club/booking.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/orders.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';
import 'package:openni_club/wechat_gateway.dart';

class TestWechat implements WechatGateway {
  TestWechat({this.unavailableReason});

  @override
  final String? unavailableReason;
  int authentications = 0, payments = 0;

  @override
  Future<String> authenticate() async {
    authentications++;
    return 'wechat-proof';
  }

  @override
  Future<void> pay(Map<String, dynamic> parameters) async {
    payments++;
  }
}

Finder fieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && (widget.autofillHints?.contains(hint) ?? false),
);

Finder get phoneField => fieldWithHint(AutofillHints.telephoneNumberNational);
Finder get otpField => fieldWithHint(AutofillHints.oneTimeCode);
Finder get authAction => find.descendant(
  of: find.byType(AuthPage),
  matching: find.byType(FilledButton),
);

http.Response jsonResponse(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> capabilities({bool sms = true, bool wechat = false}) => {
  'mode': 'production',
  'wechatApp': {'enabled': wechat},
  'sms': {'enabled': sms, 'provider': sms ? 'tencent' : 'disabled'},
};

void mobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<GoRouter> pumpAuth(
  WidgetTester tester,
  ClubRepository repo, {
  String kind = 'phone',
  String next = '/',
}) async {
  mobileSize(tester);
  final router = GoRouter(
    initialLocation: kind == 'welcome' ? '/welcome' : '/login',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, _) => AuthPage(repo, kind: 'welcome', next: next),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) => AuthPage(
          repo,
          kind: kind == 'welcome' ? 'login' : kind,
          next: state.uri.queryParameters['next'] ?? next,
        ),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(key: ValueKey('returned-home')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderPage(repo, state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/services',
        builder: (_, _) => const Scaffold(key: ValueKey('returned-services')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(repo.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: clubTheme(repo), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> tapAuthAction(WidgetTester tester) async {
  await tester.ensureVisible(authAction);
  await tester.tap(authAction);
  await tester.pumpAndSettle();
}

Future<void> requestCode(WidgetTester tester) async {
  await tester.enterText(phoneField, '13800138000');
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tapAuthAction(tester);
  expect(otpField, findsOneWidget);
}

Future<void> reviewBooking(WidgetTester tester) async {
  final playerPicker = find.byIcon(Icons.person_search_outlined);
  await tester.ensureVisible(playerPicker);
  await tester.tap(playerPicker);
  await tester.pumpAndSettle();
  await tester.tap(find.text('测试陪练'));
  await tester.pumpAndSettle();

  final slot = find.widgetWithText(OutlinedButton, '20:00');
  await tester.ensureVisible(slot);
  await tester.tap(slot);
  final contact = find.byType(TextFormField).first;
  final note = find.byType(TextFormField).last;
  await tester.ensureVisible(contact);
  await tester.enterText(contact, 'booking-contact');
  await tester.ensureVisible(note);
  await tester.enterText(note, 'booking-note');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();

  final action = find.descendant(
    of: find.byType(BookingPage),
    matching: find.byType(FilledButton),
  );
  expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.byType(TextFormField), findsNothing);
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  expect(
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
    isTrue,
  );
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.byType(AuthPage), findsOneWidget);
}

void main() {
  testWidgets('welcome login completes at the original next route', (
    tester,
  ) async {
    var requests = 0;
    final repo = ClubRepository(
      persist: false,
      client: MockClient((request) async {
        requests++;
        throw StateError('Local welcome login must not use HTTP');
      }),
    );
    final next = Uri(
      path: '/services',
      queryParameters: {'game': '三角洲行动'},
    ).toString();
    final router = await pumpAuth(tester, repo, kind: 'welcome', next: next);
    expect(tester.widget<AuthPage>(find.byType(AuthPage)).kind, 'welcome');

    await tapAuthAction(tester);
    expect(tester.widget<AuthPage>(find.byType(AuthPage)).kind, 'login');
    expect(phoneField, findsNothing);
    await tapAuthAction(tester);
    expect(phoneField, findsOneWidget);
    await requestCode(tester);
    await tester.enterText(otpField, '123456');
    await tapAuthAction(tester);

    expect(find.byKey(const ValueKey('returned-services')), findsOneWidget);
    expect(find.byType(AuthPage), findsNothing);
    expect(router.routeInformationProvider.value.uri.toString(), next);
    expect(repo.token, 'local-preview-session');
    expect(requests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelled welcome login remains on welcome without a session', (
    tester,
  ) async {
    var requests = 0;
    final repo = ClubRepository(
      persist: false,
      client: MockClient((request) async {
        requests++;
        throw StateError('Cancelling local login must not use HTTP');
      }),
    );
    final router = await pumpAuth(
      tester,
      repo,
      kind: 'welcome',
      next: '/services?game=test',
    );
    final welcomeState = tester.state(find.byType(AuthPage));
    await tapAuthAction(tester);
    expect(tester.widget<AuthPage>(find.byType(AuthPage)).kind, 'login');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(tester.widget<AuthPage>(find.byType(AuthPage)).kind, 'welcome');
    expect(tester.state(find.byType(AuthPage)), same(welcomeState));
    expect(router.routeInformationProvider.value.uri.path, '/welcome');
    expect(find.byKey(const ValueKey('returned-services')), findsNothing);
    expect(repo.token, isNull);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'return intent permits internal paths and rejects external or login loops',
    () {
      const intent = '/book?service=s1&variant=pc-120&player=p1';
      expect(safeReturnPath(intent), intent);
      expect(safeReturnPath('/orders/o1?intent=pay'), '/orders/o1?intent=pay');
      for (final value in [
        null,
        '',
        'https://other.example/orders/o1',
        '//other.example/orders/o1',
        'javascript:alert(1)',
        'orders/o1',
        '/login',
        '/login/phone?next=/login',
      ]) {
        expect(safeReturnPath(value), '/', reason: 'Unsafe return: $value');
      }
    },
  );

  testWidgets(
    'phone login requires consent and accepts a pasted six digit OTP',
    (tester) async {
      mobileSize(tester);
      var requests = 0;
      final repo = ClubRepository(
        persist: false,
        client: MockClient((request) async {
          requests++;
          throw StateError('Local login must not use HTTP');
        }),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        OpenNIApp(repository: repo, initialScreen: 'phone'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(phoneField, '+86 138-0013-8000');
      expect(
        tester.widget<TextField>(phoneField).controller!.text,
        '13800138000',
      );
      await tapAuthAction(tester);
      expect(phoneField, findsOneWidget);
      expect(otpField, findsNothing);
      expect(repo.token, isNull);
      expect(
        find.descendant(
          of: find.byType(AuthPage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tapAuthAction(tester);
      expect(otpField, findsOneWidget);
      expect(
        tester.widget<TextField>(otpField).keyboardType,
        TextInputType.number,
      );
      await tester.enterText(otpField, '12a34 56789');
      expect(tester.widget<TextField>(otpField).controller!.text, '123456');
      expect(repo.token, isNull, reason: 'Pasting a code must not submit it');
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wrong OTP stays in place and successful login returns without paying',
    (tester) async {
      final requests = <http.Request>[];
      final sdk = TestWechat();
      final order = <String, dynamic>{
        'id': 'o1',
        'serviceId': 's1',
        'serviceTitle': '预约服务',
        'serviceSnapshot': {'game': '测试游戏', 'durationMinutes': 60},
        'priceCents': 3600,
        'status': 'pending',
        'fulfillmentStatus': 'awaiting_payment',
        'paymentStatus': 'unpaid',
        'scheduledAt': '2030-01-02T12:00:00Z',
        'createdAt': '2030-01-01T12:00:00Z',
        'contact': 'contact',
      };
      final repo =
          ClubRepository(
              baseUrl: 'https://club.example/api/v1',
              appMode: 'production',
              persist: false,
              wechat: sdk,
              client: MockClient((request) async {
                requests.add(request);
                switch (request.url.path) {
                  case '/api/v1/auth/capabilities':
                    return jsonResponse(capabilities());
                  case '/api/v1/auth/sms/challenges':
                    return jsonResponse({
                      'challengeId': 'challenge',
                      'phoneMasked': '138****8000',
                      'delivery': 'accepted',
                      'retryAfterSeconds': 60,
                      'expiresInSeconds': 300,
                    }, status: 201);
                  case '/api/v1/auth/sms/verify':
                    if (jsonDecode(request.body)['code'] != '739162') {
                      return jsonResponse({
                        'error': {
                          'code': 'OTP_INVALID',
                          'message': '验证码不正确',
                          'attemptsRemaining': 4,
                        },
                      }, status: 401);
                    }
                    return jsonResponse({
                      'token': 'verified-session',
                      'user': {'id': 'u1', 'name': '手机用户'},
                      'role': 'customer',
                    });
                  case '/api/v1/me':
                    return jsonResponse({
                      'user': {'id': 'u1', 'name': '手机用户'},
                      'role': 'customer',
                      'playerId': null,
                    });
                  case '/api/v1/orders/o1':
                    return jsonResponse(order);
                  default:
                    throw StateError(
                      'Unexpected request: ${request.method} ${request.url.path}',
                    );
                }
              }),
            )
            ..orders = [order]
            ..club = {
              'privacyText': 'Privacy',
              'termsText': 'Terms',
              'supportContact': 'support@example.test',
            };
      final router = await pumpAuth(
        tester,
        repo,
        next: '/orders/o1?intent=pay',
      );
      await requestCode(tester);
      await tester.enterText(otpField, '000000');
      await tapAuthAction(tester);
      expect(otpField, findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(repo.token, isNull);
      expect(find.byType(OrderPage), findsNothing);

      await tester.enterText(otpField, '739162');
      await tapAuthAction(tester);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/orders/o1?intent=pay',
      );
      expect(find.byType(OrderPage), findsOneWidget);
      expect(repo.token, 'verified-session');
      expect(repo.orders.single['paymentStatus'], 'unpaid');
      expect(
        requests.where((request) => request.url.path.endsWith('/pay')),
        isEmpty,
      );
      expect(sdk.payments, 0);
      expect(sdk.authentications, 0);
      expect(tester.takeException(), isNull);

      // A session can expire while the order stays open. Payment must still
      // require a new explicit action after the login route returns.
      repo.token = null;
      final paymentAction = find.descendant(
        of: find.byType(OrderPage),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(paymentAction);
      await tester.tap(paymentAction);
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      await requestCode(tester);
      await tester.enterText(otpField, '739162');
      await tapAuthAction(tester);
      expect(find.byType(AuthPage), findsNothing);
      expect(find.byType(OrderPage), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/orders/o1?intent=pay',
      );
      expect(repo.token, 'verified-session');
      expect(repo.orders.single['paymentStatus'], 'unpaid');
      expect(
        requests.where((request) => request.url.path.endsWith('/pay')),
        isEmpty,
      );
      expect(sdk.payments, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'resend uses server retryAfterSeconds and injected repository time',
    (tester) async {
      var now = DateTime.utc(2030, 1, 1, 12);
      var challenges = 0;
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        appMode: 'production',
        persist: false,
        clock: () => now,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/capabilities')) {
            return jsonResponse(capabilities());
          }
          expect(request.url.path, '/api/v1/auth/sms/challenges');
          challenges++;
          return jsonResponse({
            'challengeId': 'challenge-$challenges',
            'phoneMasked': '138****8000',
            'delivery': 'accepted',
            'retryAfterSeconds': 7,
            'expiresInSeconds': 300,
          }, status: 201);
        }),
      );
      await pumpAuth(tester, repo);
      await requestCode(tester);
      final resend = find.descendant(
        of: find.byType(AuthPage),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(
        (tester.widget<TextButton>(resend).child as Text).data,
        startsWith('7s '),
      );
      now = now.add(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(
        (tester.widget<TextButton>(resend).child as Text).data,
        startsWith('1s '),
      );
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);

      await tester.enterText(otpField, '123456');
      await tester.ensureVisible(resend);
      await tester.tap(resend);
      await tester.pumpAndSettle();
      expect(challenges, 2);
      expect(tester.widget<TextField>(otpField).controller!.text, isEmpty);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(
        (tester.widget<TextButton>(resend).child as Text).data,
        startsWith('7s '),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unavailable production providers cannot initiate authentication',
    (tester) async {
      final sdk = TestWechat();
      final requests = <String>[];
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        appMode: 'production',
        persist: false,
        wechat: sdk,
        client: MockClient((request) async {
          requests.add(request.url.path);
          return jsonResponse(capabilities(sms: false, wechat: false));
        }),
      );
      await pumpAuth(tester, repo, kind: 'login');
      expect(tester.widget<FilledButton>(authAction).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(phoneField, findsNothing);
      expect(sdk.authentications, 0);
      expect(requests, ['/api/v1/auth/capabilities']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'direct production phone route stays disabled when SMS is unavailable',
    (tester) async {
      final requests = <String>[];
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        appMode: 'production',
        persist: false,
        client: MockClient((request) async {
          requests.add(request.url.path);
          return jsonResponse(capabilities(sms: false));
        }),
      );
      await pumpAuth(tester, repo);
      await tester.enterText(phoneField, '13800138000');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(authAction).onPressed, isNull);
      await tester.showKeyboard(phoneField);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(requests, ['/api/v1/auth/capabilities']);
      expect(repo.token, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pending challenge cannot override back navigation', (
    tester,
  ) async {
    for (final status in [201, 502]) {
      final pending = Completer<http.Response>();
      final requests = <String>[];
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        appMode: 'production',
        persist: false,
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/auth/capabilities')) {
            return jsonResponse(capabilities());
          }
          expect(request.url.path, '/api/v1/auth/sms/challenges');
          return pending.future;
        }),
      );
      final router = await pumpAuth(tester, repo);
      await tester.enterText(phoneField, '13800138000');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(authAction);
      await tester.tap(authAction);
      await tester.pump();
      expect(pending.isCompleted, isFalse);
      expect(requests, [
        '/api/v1/auth/capabilities',
        '/api/v1/auth/sms/challenges',
      ]);
      expect(tester.widget<FilledButton>(authAction).onPressed, isNull);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      expect(phoneField, findsNothing);
      expect(otpField, findsNothing);
      expect(tester.widget<FilledButton>(authAction).onPressed, isNotNull);

      pending.complete(
        status == 201
            ? jsonResponse({
                'challengeId': 'late-challenge',
                'phoneMasked': '138****8000',
                'delivery': 'accepted',
                'retryAfterSeconds': 60,
                'expiresInSeconds': 300,
              }, status: status)
            : jsonResponse({
                'error': {'code': 'SMS_DELIVERY_FAILED', 'message': '迟到的请求错误'},
              }, status: status),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(phoneField, findsNothing);
      expect(otpField, findsNothing);
      expect(find.text('迟到的请求错误'), findsNothing);
      expect(tester.widget<FilledButton>(authAction).onPressed, isNotNull);
      expect(repo.token, isNull);
      expect(requests, [
        '/api/v1/auth/capabilities',
        '/api/v1/auth/sms/challenges',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final smsEnabled in [true, false]) {
    testWidgets(
      smsEnabled
          ? 'production booking supports SMS without WeChat and never auto submits after login'
          : 'production booking with both providers disabled cannot authenticate or create orders',
      (tester) async {
        mobileSize(tester);
        final requests = <http.Request>[];
        final sdk = TestWechat(unavailableReason: '测试环境没有微信 SDK');
        final repo =
            ClubRepository(
                baseUrl: 'https://club.example/api/v1',
                appMode: 'production',
                persist: false,
                clock: () => DateTime.utc(2030, 1, 1, 12),
                wechat: sdk,
                client: MockClient((request) async {
                  requests.add(request);
                  switch (request.url.path) {
                    case '/api/v1/players/p1/availability':
                      expect(request.method, 'GET');
                      expect(request.url.queryParameters, {
                        'date': '2030-01-02',
                        'durationMinutes': '60',
                      });
                      return jsonResponse({
                        'slots': [
                          {
                            'startAt': '2030-01-02T12:00:00Z',
                            'endAt': '2030-01-02T13:00:00Z',
                            'available': true,
                            'busy': false,
                          },
                        ],
                      });
                    case '/api/v1/auth/capabilities':
                      return jsonResponse(capabilities(sms: smsEnabled));
                    case '/api/v1/auth/sms/challenges':
                      expect(smsEnabled, isTrue);
                      expect(jsonDecode(request.body), {
                        'phone': '13800138000',
                      });
                      return jsonResponse({
                        'challengeId': 'booking-challenge',
                        'phoneMasked': '138****8000',
                        'delivery': 'accepted',
                        'retryAfterSeconds': 60,
                        'expiresInSeconds': 300,
                      }, status: 201);
                    case '/api/v1/auth/sms/verify':
                      expect(smsEnabled, isTrue);
                      expect(jsonDecode(request.body), {
                        'challengeId': 'booking-challenge',
                        'code': '739162',
                      });
                      return jsonResponse({
                        'token': 'booking-session',
                        'user': {'id': 'u1', 'name': '手机客户'},
                        'role': 'customer',
                      });
                    case '/api/v1/me':
                      expect(
                        request.headers['authorization'],
                        'Bearer booking-session',
                      );
                      return jsonResponse({
                        'user': {'id': 'u1', 'name': '手机客户'},
                        'role': 'customer',
                        'playerId': null,
                      });
                    default:
                      throw StateError(
                        'Unexpected request: ${request.method} ${request.url.path}',
                      );
                  }
                }),
              )
              ..services = [
                {
                  'id': 's1',
                  'title': '测试服务',
                  'game': '测试游戏',
                  'durationMinutes': 60,
                  'priceCents': 3600,
                  'teamSize': 1,
                },
              ]
              ..players = [
                {
                  'id': 'p1',
                  'name': '测试陪练',
                  'role': '陪练',
                  'games': ['测试游戏'],
                },
              ]
              ..club = {
                'privacyText': 'Privacy',
                'termsText': 'Terms',
                'supportContact': 'support@example.test',
              };
        addTearDown(repo.dispose);
        await tester.pumpWidget(
          OpenNIApp(repository: repo, initialScreen: 'booking'),
        );
        await tester.pumpAndSettle();
        expect(repo.operatingUnavailable, isNull);
        expect(repo.wechatUnavailable, isNotNull);
        final originalBooking = tester.state(find.byType(BookingPage));
        final router = GoRouter.of(tester.element(find.byType(BookingPage)));
        final originalIntent = router.routeInformationProvider.value.uri
            .toString();

        await reviewBooking(tester);
        expect(repo.token, isNull);
        expect(repo.orders, isEmpty);
        expect(requests.where((request) => request.method == 'POST'), isEmpty);
        expect(sdk.authentications, 0);
        expect(sdk.payments, 0);
        final wechatAction = find.descendant(
          of: find.byType(AuthPage),
          matching: find.byType(OutlinedButton),
        );
        expect(tester.widget<OutlinedButton>(wechatAction).onPressed, isNull);

        if (smsEnabled) {
          expect(tester.widget<FilledButton>(authAction).onPressed, isNotNull);
          await tapAuthAction(tester);
          expect(phoneField, findsOneWidget);
          await requestCode(tester);
          expect(repo.token, isNull);
          expect(
            requests.where((request) => request.url.path == '/api/v1/orders'),
            isEmpty,
          );
          await tester.enterText(otpField, '739162');
          await tapAuthAction(tester);
          expect(find.byType(AuthPage), findsNothing);
          expect(find.byType(BookingPage), findsOneWidget);
          expect(tester.state(find.byType(BookingPage)), same(originalBooking));
          expect(
            router.routeInformationProvider.value.uri.toString(),
            originalIntent,
          );
          expect(repo.token, 'booking-session');
          expect(find.text('booking-contact'), findsOneWidget);
          expect(find.text('booking-note'), findsOneWidget);
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue,
          );
          expect(
            requests
                .where((request) => request.method == 'POST')
                .map((request) => request.url.path),
            ['/api/v1/auth/sms/challenges', '/api/v1/auth/sms/verify'],
          );
        } else {
          expect(tester.widget<FilledButton>(authAction).onPressed, isNull);
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(authAction).onPressed, isNull);
          expect(tester.widget<OutlinedButton>(wechatAction).onPressed, isNull);
          expect(phoneField, findsNothing);
          expect(otpField, findsNothing);
          expect(repo.token, isNull);
          expect(
            requests.where((request) => request.method == 'POST'),
            isEmpty,
          );
          expect(requests.map((request) => request.url.path), [
            '/api/v1/players/p1/availability',
            '/api/v1/auth/capabilities',
          ]);
        }
        expect(repo.orders, isEmpty);
        expect(
          requests.where((request) => request.url.path == '/api/v1/orders'),
          isEmpty,
        );
        expect(
          requests.where((request) => request.url.path.endsWith('/pay')),
          isEmpty,
        );
        expect(sdk.authentications, 0);
        expect(sdk.payments, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
