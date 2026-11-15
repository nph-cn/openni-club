import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/orders.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

import 'capture_2x.dart';
import 'catalog_media_cache.dart';

Json cloneJson(dynamic value) => Json.from(jsonDecode(jsonEncode(value)));
const captureEnabled = bool.fromEnvironment('OPENNI_CAPTURE_PRODUCT');

/// 响应由 tool/generate-flow-fixtures.mjs 的真实本地 HTTP 流程生成。
/// 测试仅回放这些响应并核对请求，不放开产品离线写入，不构造支付成功。
class ProductReplay {
  ProductReplay({this.member = false, String state = 'awaitingConfirmation'}) {
    fixture = Json.from(
      jsonDecode(File('test/fixtures/product-flow.json').readAsStringSync()),
    );
    current = cloneJson(fixture['orders'][state]);
  }
  final bool member;
  late final Json fixture;
  late Json current;
  bool failOrders = false;
  final calls = <http.Request>[];
  late final client = MockClient((request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    Object value;
    if (request.method == 'GET' && path == '/me') {
      value = fixture[member ? 'member' : 'customer'];
    } else if (request.method == 'GET' && path == '/orders') {
      if (failOrders) {
        failOrders = false;
        return response({
          'error': {
            'code': 'TEMPORARILY_UNAVAILABLE',
            'message': '暂时无法同步预约，请重试。',
          },
        }, status: 503);
      }
      value = [current];
    } else if (request.method == 'GET' && path == '/member/orders') {
      value = [current];
    } else if (request.method == 'GET' && path == '/member/earnings') {
      value = fixture['memberEarnings'];
    } else if (request.method == 'GET' && path == '/notifications') {
      value = fixture['notifications']['unread'];
    } else if (request.method == 'PATCH' &&
        path.startsWith('/notifications/') &&
        path.endsWith('/read')) {
      value = fixture['notifications']['read'];
    } else if (request.method == 'GET' && path.startsWith('/orders/')) {
      final id = path.split('/').last;
      value = id == current['id'] ? current : fixture['orders']['supportReady'];
    } else if (request.method == 'POST' && path.endsWith('/confirm')) {
      expect(jsonDecode(request.body), fixture['actions']['review']);
      current = cloneJson(fixture['orders']['completed']);
      value = current;
    } else if (request.method == 'POST' && path.endsWith('/dispute')) {
      expect(jsonDecode(request.body), fixture['actions']['dispute']);
      current = cloneJson(fixture['orders']['disputed']);
      value = current;
    } else if (request.method == 'POST' && path.endsWith('/submit')) {
      expect(jsonDecode(request.body), fixture['actions']['delivery']);
      current = cloneJson(fixture['orders']['awaitingConfirmation']);
      value = current;
    } else {
      throw StateError('截图流程中未声明的请求：${request.method} $path');
    }
    return response(value);
  });
  http.Response response(Object value, {int status = 200}) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<ClubRepository> repository() async {
    final local = ClubRepository(persist: false);
    await local.load();
    final repo =
        ClubRepository(
            baseUrl: 'https://fixture.openni.test/api/v1',
            persist: false,
            client: client,
            clock: () => DateTime.parse('${fixture['generatedAt']}'),
          )
          ..brand = local.brand
          ..club = cloneJson(fixture['club'])
          ..services = (fixture['services'] as List).map(cloneJson).toList()
          ..players = (fixture['players'] as List).map(cloneJson).toList()
          ..orders = [cloneJson(current)]
          ..token = 'isolated-widget-test-session'
          ..role = member ? 'member' : 'customer'
          ..memberPlayerId = member ? 'p1' : null
          ..memberName =
              '${fixture[member ? 'member' : 'customer']['user']['name']}';
    local.dispose();
    return repo;
  }
}

Future<GlobalKey> mountProduct(
  WidgetTester tester,
  ClubRepository repo,
  String screen,
) async {
  enableCaptureShadows();
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (captureEnabled) await tester.runAsync(primeCatalogMedia);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: OpenNIApp(
        repository: repo,
        initialScreen: screen,
        previewDevice: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (captureEnabled) {
    await tester.runAsync(
      () => primeLocalMedia(tester.element(find.byType(Scaffold).first)),
    );
  }
  await tester.pumpAndSettle();
  return key;
}

Future<void> captureProduct(
  WidgetTester tester,
  GlobalKey key,
  String id,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$id 不应有布局或运行异常');
  if (!captureEnabled) return;
  await expectLater(
    await captureAt2x(key),
    matchesGoldenFile('../screenshots/$id.png'),
  );
}

Future<void> revealProduct(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

Finder get backButton =>
    find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '返回');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (captureEnabled) setUpAll(loadCaptureFonts);

  testWidgets('成员订单分组仅显示对应状态，不把已完成排到待接单', (tester) async {
    final repo = ClubRepository(persist: false);
    await repo.load();
    await repo.loadMemberData();
    final key = await mountProduct(tester, repo, 'member_orders');
    expect(find.text('等待队友接单'), findsOneWidget);
    expect(find.text('服务已完成'), findsNothing);
    await tester.tap(find.text('服务中'));
    await tester.pumpAndSettle();
    expect(find.text('服务进行中'), findsOneWidget);
    expect(find.text('等待队友接单'), findsNothing);
    await captureProduct(tester, key, 'member_orders_active');
    await tester.tap(find.text('已结束'));
    await tester.pumpAndSettle();
    expect(find.text('服务已完成'), findsOneWidget);
    expect(find.text('服务进行中'), findsNothing);
    await captureProduct(tester, key, 'member_orders_finished');
  });

  testWidgets('客户核对交付并评价，完成后展示服务器评价与状态', (tester) async {
    final replay = ProductReplay();
    final repo = await replay.repository();
    final key = await mountProduct(tester, repo, 'order');
    expect(find.text('等待你确认完成'), findsOneWidget);
    await captureProduct(tester, key, 'order_awaiting_confirmation');
    await tester.tap(find.text('确认完成'));
    await tester.pumpAndSettle();
    expect(find.text('评价服务'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      '${replay.fixture['actions']['review']['comment']}',
    );
    await captureProduct(tester, key, 'order_rating');
    await tester.tap(find.text('确认服务完成'));
    await tester.pumpAndSettle();
    expect(stage(repo.orders.single), 'completed');
    expect(
      replay.calls.where((r) => r.url.path.endsWith('/confirm')),
      hasLength(1),
    );
    await revealProduct(tester, find.text('我的评价'));
    expect(find.text('沟通清楚，复盘建议很具体。'), findsOneWidget);
    await captureProduct(tester, key, 'order_completed');
  });

  testWidgets('售后先校验再提交，真实响应进入处理中并保留问题记录', (tester) async {
    final replay = ProductReplay(state: 'supportReady');
    final repo = await replay.repository();
    final key = await mountProduct(tester, repo, 'order');
    await tester.tap(find.text('申请售后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交售后申请'));
    await tester.pumpAndSettle();
    expect(find.text('请补充至少5个字的具体说明。'), findsOneWidget);
    expect(replay.calls.where((r) => r.method == 'POST'), isEmpty);
    await captureProduct(tester, key, 'support_validation');
    await tester.enterText(
      find.byType(TextField),
      '${replay.fixture['actions']['dispute']['details']}',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交售后申请'));
    await tester.pumpAndSettle();
    expect(stage(repo.orders.single), 'disputed');
    await revealProduct(tester, find.text('售后记录'));
    expect(
      find.text('${replay.fixture['actions']['dispute']['details']}'),
      findsOneWidget,
    );
    await captureProduct(tester, key, 'order_disputed');
  });

  testWidgets('成员填写交付记录后提交，沿用真实API结果并保留内容', (tester) async {
    final replay = ProductReplay(member: true, state: 'running');
    final repo = await replay.repository();
    // 选择实际进行中的订单，不替换离线只读演示策略。
    repo.memberOrders = [cloneJson(replay.current)];
    final key = await mountProduct(tester, repo, 'delivery');
    expect(find.text('留下这场服务的记录'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      '${replay.fixture['actions']['delivery']['summary']}',
    );
    await tester.enterText(
      find.byType(TextField).last,
      '${replay.fixture['actions']['delivery']['evidenceUrl']}',
    );
    await captureProduct(tester, key, 'delivery_filled');
    await tester.tap(find.text('提交给客户确认'));
    await tester.pumpAndSettle();
    expect(stage(repo.memberOrders.first), 'awaiting_confirmation');
    expect(find.text('已提交，等待客户确认。'), findsOneWidget);
    expect(
      replay.calls.where((r) => r.url.path.endsWith('/submit')),
      hasLength(1),
    );
  });

  testWidgets('登录后资料使用账号身份，修改昵称弹层保留现有值', (tester) async {
    final replay = ProductReplay();
    final repo = await replay.repository();
    final key = await mountProduct(tester, repo, 'profile');
    expect(find.text('林同学'), findsOneWidget);
    expect(find.text('欢迎来到俱乐部'), findsNothing);
    await captureProduct(tester, key, 'profile_signed_in');
    await revealProduct(tester, find.text('设置与关于'));
    await tester.tap(find.text('设置与关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改昵称'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '林同学',
    );
    await captureProduct(tester, key, 'profile_edit_name');
  });

  testWidgets('通知显示日期时间与未读，打开关联订单后本页同步已读', (tester) async {
    final replay = ProductReplay();
    final repo = await replay.repository();
    final key = await mountProduct(tester, repo, 'notifications');
    final originalUnread = repo.notifications
        .where((n) => n['readAt'] == null)
        .length;
    expect(originalUnread, greaterThan(0));
    expect(find.text('21:00'), findsWidgets);
    await captureProduct(tester, key, 'notifications_inbox');
    await tester.tap(find.text('服务记录已提交').first);
    await tester.pumpAndSettle();
    expect(find.byType(OrderPage), findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(
      repo.notifications.where((n) => n['readAt'] == null).length,
      originalUnread - 1,
    );
    expect(
      replay.calls.where(
        (r) => r.method == 'PATCH' && r.url.path.endsWith('/read'),
      ),
      hasLength(1),
    );
  });

  testWidgets('订单同步失败保留重试，恢复后显示真实订单', (tester) async {
    final replay = ProductReplay()..failOrders = true;
    final repo = await replay.repository();
    repo.orders = [];
    final key = await mountProduct(tester, repo, 'orders');
    expect(find.text('订单加载失败'), findsOneWidget);
    await captureProduct(tester, key, 'orders_retry');
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('订单加载失败'), findsNothing);
    expect(find.text('等待你确认完成'), findsOneWidget);
    expect(repo.orders.single['id'], replay.current['id']);
  });
}
