import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/wechat_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response responseOf(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final sessionChanged = throwsA(
  isA<ClubApiException>().having(
    (error) => error.code,
    'code',
    'SESSION_CHANGED',
  ),
);

class WaitingWechat implements WechatGateway {
  final started = Completer<void>();
  final response = Completer<String>();
  @override
  String? get unavailableReason => null;
  @override
  Future<String> authenticate() {
    started.complete();
    return response.future;
  }

  @override
  Future<void> pay(Map<String, dynamic> parameters) async =>
      throw StateError('该测试不得调用支付');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('退出后在途个人资料、订单和通知不能恢复旧账号状态', () async {
    final responses = <String, Completer<http.Response>>{};
    final started = Completer<void>();
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient((request) {
        responses[request.url.path] = Completer<http.Response>();
        if (responses.length == 3) started.complete();
        return responses[request.url.path]!.future;
      }),
    )..token = 'session-a';
    final account = expectLater(repo.loadAccount(), sessionChanged);
    final orders = expectLater(repo.refreshOrders(), sessionChanged);
    final notices = expectLater(
      repo.request('GET', '/notifications'),
      sessionChanged,
    );
    await started.future;
    await repo.signOut();
    responses['/api/v1/me']!.complete(
      responseOf('"旧响应即使不是预期对象也应先被会话守卫丢弃"', 200),
    );
    responses['/api/v1/orders']!.complete(
      responseOf('[{"id":"old-order"}]', 200),
    );
    responses['/api/v1/notifications']!.complete(
      responseOf('[{"id":"old-notification"}]', 200),
    );
    await Future.wait([account, orders, notices]);
    expect(repo.token, isNull);
    expect(repo.role, 'customer');
    expect(repo.memberName, '新朋友');
    expect(repo.orders, isEmpty);
    expect(repo.notifications, isEmpty);
  });

  for (final status in [200, 401]) {
    test('切到新会话后旧账号 $status 响应不能覆盖或清除新会话', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final repo = ClubRepository(
        baseUrl: 'https://club.example/api/v1',
        persist: false,
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      )..token = 'session-a';
      final pending = expectLater(repo.loadAccount(), sessionChanged);
      await started.future;
      await repo.signOut();
      repo
        ..token = 'session-b'
        ..memberName = '新账号'
        ..role = 'customer';
      response.complete(
        responseOf(
          jsonEncode(
            status == 200
                ? {
                    'role': 'member',
                    'playerId': 'old-player',
                    'user': {'name': '旧账号'},
                  }
                : {
                    'error': {'code': 'UNAUTHORIZED', 'message': '旧会话过期'},
                  },
          ),
          status,
        ),
      );
      await pending;
      expect(repo.token, 'session-b');
      expect(repo.memberName, '新账号');
      expect(repo.role, 'customer');
      expect(repo.memberPlayerId, isNull);
    });
  }

  test('退出后成员订单和收入读取不能恢复成员缓存', () async {
    final responses = <String, Completer<http.Response>>{};
    final started = Completer<void>();
    final repo =
        ClubRepository(
            baseUrl: 'https://club.example/api/v1',
            persist: false,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/me')) {
                return responseOf(
                  '{"role":"member","playerId":"p1","user":{"name":"成员"}}',
                  200,
                );
              }
              responses[request.url.path] = Completer<http.Response>();
              if (responses.length == 2) started.complete();
              return responses[request.url.path]!.future;
            }),
          )
          ..token = 'member-session'
          ..notifications = [
            {'id': 'old-notification'},
          ];
    final pending = expectLater(repo.loadMemberData(), sessionChanged);
    await started.future;
    await repo.signOut();
    responses['/api/v1/member/orders']!.complete(responseOf('[]', 200));
    responses['/api/v1/member/earnings']!.complete(
      responseOf('{"totalCents":100}', 200),
    );
    await pending;
    expect(repo.role, 'customer');
    expect(repo.memberOrders, isEmpty);
    expect(repo.earnings, isEmpty);
    expect(repo.notifications, isEmpty);
  });

  test('旧公开请求的 401 也不能清除新会话', () async {
    final response = Completer<http.Response>();
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient((_) => response.future),
    )..token = 'session-a';
    final pending = expectLater(repo.request('GET', '/club'), throwsException);
    repo.token = 'session-b';
    response.complete(responseOf('{"error":{"message":"过期"}}', 401));
    await pending;
    expect(repo.token, 'session-b');
  });

  test('当前会话的 401 仍然清除已失效 token', () async {
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient(
        (_) async => responseOf('{"error":{"message":"过期"}}', 401),
      ),
    )..token = 'expired-session';
    await expectLater(repo.refreshOrders(), throwsException);
    expect(repo.token, isNull);
  });

  test('token 仍为空时退出可撤销在途登录响应', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final pending = expectLater(repo.signIn(), sessionChanged);
    await started.future;
    await repo.signOut();
    response.complete(responseOf('{"token":"late-session"}', 200));
    await pending;
    expect(repo.token, isNull);
  });

  test('等待微信返回期间退出不会再发送登录请求', () async {
    final wechat = WaitingWechat();
    var requests = 0;
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      wechat: wechat,
      client: MockClient((_) async {
        requests++;
        return responseOf('{"token":"late-session"}', 200);
      }),
    );
    final pending = expectLater(repo.signInWithWechat(), sessionChanged);
    await wechat.started.future;
    await repo.signOut();
    wechat.response.complete('oauth-code');
    await pending;
    expect(requests, 0);
    expect(repo.token, isNull);
  });

  test('API 模式关注可在重载后恢复且不存 token、远程订单或账号资料', () async {
    SharedPreferences.setMockInitialValues({
      'openni_demo_orders': '[{"id":"local-only"}]',
      'openni_name': '本地演示名',
    });
    ClubRepository makeRepo() => ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      appMode: 'production',
      client: MockClient(
        (request) async => responseOf(
          request.url.path.endsWith('/club') ? '{"demoData":false}' : '[]',
          200,
        ),
      ),
    );
    final repo = makeRepo();
    await repo.load();
    expect(repo.error, isNull);
    repo
      ..token = 'private-session'
      ..memberName = '远程用户'
      ..orders = [
        {'id': 'remote-order'},
      ];
    await repo.toggleFollow('p1');
    await repo.signOut();
    final restored = makeRepo();
    await restored.load();
    expect(restored.following, {'p1'});
    expect(restored.orders, isEmpty);
    expect(restored.token, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('openni_demo_orders'), '[{"id":"local-only"}]');
    expect(prefs.getString('openni_name'), '本地演示名');
    expect(prefs.getKeys(), {
      'openni_demo_orders',
      'openni_name',
      'openni_following',
    });
    await restored.toggleFollow('p1');
    final afterUnfollow = makeRepo();
    await afterUnfollow.load();
    expect(afterUnfollow.following, isEmpty);
  });

  test('退出本地演示保留预约和关注且不调用账号删除接口', () async {
    var requests = 0;
    final repo =
        ClubRepository(
            persist: false,
            client: MockClient((_) async {
              requests++;
              return responseOf('{}', 200);
            }),
          )
          ..token = 'local-preview-session'
          ..orders = [
            {'id': 'local-order'},
          ];
    repo.following.add('p1');
    await repo.signOut();
    expect(repo.orders.single['id'], 'local-order');
    expect(repo.following, {'p1'});
    expect(requests, 0);
    expect(repo.token, isNull);
  });
}
