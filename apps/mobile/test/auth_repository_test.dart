import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openni_club/repository.dart';

Matcher apiError(
  String code, {
  int? retryAfterSeconds,
  int? attemptsRemaining,
}) => isA<ClubApiException>()
    .having((error) => error.code, 'code', code)
    .having(
      (error) => error.retryAfterSeconds,
      'retryAfterSeconds',
      retryAfterSeconds,
    )
    .having(
      (error) => error.attemptsRemaining,
      'attemptsRemaining',
      attemptsRemaining,
    );

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('local SMS preview', () {
    late DateTime now;
    late ClubRepository repo;
    late int httpCalls;

    setUp(() {
      now = DateTime.utc(2030, 1, 1, 12);
      httpCalls = 0;
      repo = ClubRepository(
        baseUrl: '',
        appMode: 'demo',
        persist: false,
        clock: () => now,
        client: MockClient((request) async {
          httpCalls++;
          throw StateError('Local preview must never make an HTTP request');
        }),
      );
    });

    tearDown(() {
      expect(httpCalls, 0);
      repo.dispose();
    });

    test(
      'capabilities and challenge explicitly identify unsent test code',
      () async {
        final capabilities = await repo.loadAuthCapabilities();
        expect(capabilities['mode'], 'demo');
        expect(capabilities['wechatApp']['enabled'], isFalse);
        expect(capabilities['sms']['enabled'], isTrue);
        expect(capabilities['sms']['provider'], 'test');
        expect(capabilities['sms']['testMode'], isTrue);

        final challenge = await repo.requestSmsChallenge('  +8613800138000  ');
        expect(
          challenge['challengeId'],
          isA<String>().having((s) => s.isNotEmpty, 'not empty', isTrue),
        );
        expect(challenge['phoneMasked'], '138****8000');
        expect(challenge['delivery'], 'test');
        expect(challenge['testCode'], matches(RegExp(r'^[0-9]{6}$')));
        expect(challenge['expiresInSeconds'], 300);
        expect(challenge['retryAfterSeconds'], 60);
        expect(repo.token, isNull);

        await repo.verifySms(challenge['challengeId'], challenge['testCode']);
        expect(repo.token, 'local-preview-session');
        expect(repo.role, 'customer');
        expect(repo.memberPlayerId, isNull);
        expect(repo.memberName, '手机用户');
      },
    );

    test('invalid phone is rejected before issuing a challenge', () async {
      for (final phone in [
        '12800138000',
        '138-0013-8000',
        '+1 3800138000',
        '',
      ]) {
        await expectLater(
          repo.requestSmsChallenge(phone),
          throwsA(apiError('PHONE_INVALID')),
        );
      }
      final challenge = await repo.requestSmsChallenge('13800138000');
      expect(challenge['delivery'], 'test');
    });

    test(
      'wrong and malformed codes count toward the five-attempt lock',
      () async {
        final challenge = await repo.requestSmsChallenge('13800138000');
        final id = challenge['challengeId'] as String;
        for (var attempt = 1; attempt <= 5; attempt++) {
          await expectLater(
            repo.verifySms(id, attempt == 1 ? 'abc' : '000000'),
            throwsA(apiError('OTP_INVALID', attemptsRemaining: 5 - attempt)),
          );
          expect(repo.token, isNull);
        }
        await expectLater(
          repo.verifySms(id, challenge['testCode']),
          throwsA(apiError('OTP_ATTEMPTS_EXCEEDED', retryAfterSeconds: 60)),
        );
        expect(repo.token, isNull);
      },
    );

    test('challenge expires exactly at its declared expiry', () async {
      final challenge = await repo.requestSmsChallenge('13800138000');
      now = now.add(Duration(seconds: challenge['expiresInSeconds'] as int));
      await expectLater(
        repo.verifySms(challenge['challengeId'], challenge['testCode']),
        throwsA(apiError('OTP_EXPIRED')),
      );
      expect(repo.token, isNull);
    });

    test('consumed challenge cannot create another session', () async {
      final challenge = await repo.requestSmsChallenge('13800138000');
      await repo.verifySms(challenge['challengeId'], challenge['testCode']);
      repo.token = null;
      await expectLater(
        repo.verifySms(challenge['challengeId'], challenge['testCode']),
        throwsA(apiError('OTP_USED')),
      );
      expect(repo.token, isNull);
    });

    test(
      'cooldown uses injected time and permits resend at its boundary',
      () async {
        final first = await repo.requestSmsChallenge('13800138000');
        await expectLater(
          repo.requestSmsChallenge('13800138000'),
          throwsA(apiError('SMS_COOLDOWN', retryAfterSeconds: 60)),
        );
        now = now.add(const Duration(seconds: 59));
        await expectLater(
          repo.requestSmsChallenge('13800138000'),
          throwsA(apiError('SMS_COOLDOWN', retryAfterSeconds: 1)),
        );
        now = now.add(const Duration(seconds: 1));
        final second = await repo.requestSmsChallenge('13800138000');
        expect(second['challengeId'], isNot(first['challengeId']));
        expect(second['delivery'], 'test');
        await repo.verifySms(second['challengeId'], second['testCode']);
        expect(repo.token, 'local-preview-session');
      },
    );
  });

  group('remote SMS authentication', () {
    test(
      'verification sends only proof and refreshes authoritative account',
      () async {
        final requests = <http.Request>[];
        final repo =
            ClubRepository(
                baseUrl: 'https://club.example/api/v1',
                appMode: 'production',
                persist: false,
                client: MockClient((request) async {
                  requests.add(request);
                  if (request.url.path == '/api/v1/auth/sms/verify') {
                    expect(request.method, 'POST');
                    expect(jsonDecode(request.body), {
                      'challengeId': 'server-challenge',
                      'code': '739162',
                    });
                    return jsonResponse({
                      'token': 'server-session',
                      'user': {'id': 'u-verified', 'name': '登录响应昵称'},
                      'role': 'customer',
                      'playerId': null,
                    });
                  }
                  expect(request.url.path, '/api/v1/me');
                  expect(request.method, 'GET');
                  expect(
                    request.headers['authorization'],
                    'Bearer server-session',
                  );
                  return jsonResponse({
                    'user': {'id': 'u-verified', 'name': '已验证成员'},
                    'role': 'member',
                    'playerId': 'p-authoritative',
                  });
                }),
              )
              ..role = 'untrusted-client-role'
              ..memberPlayerId = 'untrusted-client-player';
        addTearDown(repo.dispose);

        await repo.verifySms('server-challenge', '739162');
        expect(requests, hasLength(2));
        expect(repo.token, 'server-session');
        expect(repo.role, 'member');
        expect(repo.memberPlayerId, 'p-authoritative');
        expect(repo.memberName, '已验证成员');
      },
    );

    test(
      'challenge request preserves accepted delivery without inventing a code',
      () async {
        final repo = ClubRepository(
          baseUrl: 'https://club.example/api/v1',
          appMode: 'production',
          persist: false,
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/auth/sms/challenges');
            expect(jsonDecode(request.body), {'phone': '13800138000'});
            return jsonResponse({
              'challengeId': 'provider-challenge',
              'phoneMasked': '138****8000',
              'expiresInSeconds': 300,
              'retryAfterSeconds': 45,
              'delivery': 'accepted',
            }, status: 201);
          }),
        );
        addTearDown(repo.dispose);

        final challenge = await repo.requestSmsChallenge(' +8613800138000 ');
        expect(challenge['delivery'], 'accepted');
        expect(challenge['retryAfterSeconds'], 45);
        expect(challenge.containsKey('testCode'), isFalse);
        expect(repo.token, isNull);
      },
    );

    test(
      'OTP_INVALID 401 retains the existing session and attempts metadata',
      () async {
        var requests = 0;
        final repo =
            ClubRepository(
                baseUrl: 'https://club.example/api/v1',
                appMode: 'production',
                persist: false,
                client: MockClient((request) async {
                  requests++;
                  expect(request.url.path, '/api/v1/auth/sms/verify');
                  return jsonResponse({
                    'error': {
                      'code': 'OTP_INVALID',
                      'message': '验证码不正确',
                      'attemptsRemaining': 4,
                    },
                  }, status: 401);
                }),
              )
              ..token = 'existing-session'
              ..role = 'member'
              ..memberPlayerId = 'existing-player';
        addTearDown(repo.dispose);

        await expectLater(
          repo.verifySms('challenge', '000000'),
          throwsA(apiError('OTP_INVALID', attemptsRemaining: 4)),
        );
        expect(requests, 1);
        expect(repo.token, 'existing-session');
        expect(repo.role, 'member');
        expect(repo.memberPlayerId, 'existing-player');
      },
    );

    test(
      'typed retry error retains server cooldown and remaining attempts',
      () async {
        final repo = ClubRepository(
          baseUrl: 'https://club.example/api/v1',
          persist: false,
          client: MockClient(
            (request) async => jsonResponse({
              'error': {
                'code': 'OTP_ATTEMPTS_EXCEEDED',
                'message': '尝试次数过多',
                'retryAfterSeconds': 47,
                'attemptsRemaining': 0,
              },
            }, status: 429),
          ),
        );
        addTearDown(repo.dispose);
        await expectLater(
          repo.verifySms('challenge', '123456'),
          throwsA(
            apiError(
              'OTP_ATTEMPTS_EXCEEDED',
              retryAfterSeconds: 47,
              attemptsRemaining: 0,
            ),
          ),
        );
        expect(repo.token, isNull);
      },
    );

    test(
      'production without an API cannot fall back to local fixtures',
      () async {
        final requestedPaths = <String>[];
        final repo = ClubRepository(
          baseUrl: '',
          appMode: 'production',
          persist: false,
          client: MockClient((request) async {
            requestedPaths.add(request.url.path);
            return jsonResponse({
              'error': {'code': 'SMS_NOT_CONFIGURED', 'message': '短信登录尚未配置'},
            }, status: 503);
          }),
        );
        addTearDown(repo.dispose);

        await expectLater(
          repo.loadAuthCapabilities(),
          throwsA(apiError('SMS_NOT_CONFIGURED')),
        );
        await expectLater(
          repo.requestSmsChallenge('13800138000'),
          throwsA(apiError('SMS_NOT_CONFIGURED')),
        );
        await expectLater(
          repo.verifySms('local-1', '123456'),
          throwsA(apiError('SMS_NOT_CONFIGURED')),
        );
        expect(requestedPaths, [
          '/auth/capabilities',
          '/auth/sms/challenges',
          '/auth/sms/verify',
        ]);
        expect(repo.authCapabilities, isNull);
        expect(repo.token, isNull);
      },
    );
  });
}
