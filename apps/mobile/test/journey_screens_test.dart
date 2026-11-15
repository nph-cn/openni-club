import 'capture_2x.dart';
import 'catalog_media_cache.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

Future<({ClubRepository repo, GlobalKey key})> startJourney(
  WidgetTester tester,
  String screen,
) async {
  enableCaptureShadows();
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = ClubRepository(
    persist: false,
    clock: () => DateTime.utc(2026, 11, 16, 5),
  );
  await repo.load();
  await tester.runAsync(primeCatalogMedia);
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
  await tester.runAsync(
    () => primeLocalMedia(tester.element(find.byType(Scaffold).first)),
  );
  await tester.pumpAndSettle();
  return (repo: repo, key: key);
}

Future<void> captureJourney(
  WidgetTester tester,
  GlobalKey key,
  String id,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$id 不应出现布局或运行错误');
  // 首次建立基线前可只验证完整操作；默认仍必须逐张比对真实截图。
  if (const bool.fromEnvironment('OPENNI_JOURNEY_ASSERTIONS_ONLY')) return;
  await expectLater(
    await captureAt2x(key),
    matchesGoldenFile('../screenshots/$id.png'),
  );
}

Future<void> finishJourney(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  // 浮动底部操作栏可能盖住滚动区域边缘，将目标滚到内容区中段。
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCaptureFonts);

  testWidgets('真实目录操作：搜索、无结果、游戏筛选与陪练筛选', (tester) async {
    final session = await startJourney(tester, 'services');
    await tester.enterText(find.byType(EditableText), '复盘');
    await tester.pumpAndSettle();
    expect(find.text('三角洲 · 对局复盘'), findsOneWidget);
    expect(find.text('三角洲 · PC 小时陪'), findsNothing);
    await captureJourney(tester, session.key, 'services_search');

    await tester.enterText(find.byType(EditableText), '不存在的服务');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务'), findsOneWidget);
    await captureJourney(tester, session.key, 'services_search_empty');

    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    final game = find.widgetWithText(ChoiceChip, '无畏契约');
    await tester.ensureVisible(game);
    await tester.tap(game);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(game).selected, isTrue);
    expect(find.text('三角洲 · PC 小时陪'), findsNothing);
    await captureJourney(tester, session.key, 'services_game_filter');

    await tester.tap(find.text('俱乐部陪练'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '阿屿');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '阿屿'),
      findsOneWidget,
    );
    expect(find.text('Echo'), findsNothing);
    await captureJourney(tester, session.key, 'players_search');

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '本机关注'));
    await tester.pumpAndSettle();
    expect(find.text('还没有本机关注'), findsOneWidget);
    await captureJourney(tester, session.key, 'players_following_empty');
    await finishJourney(tester);
  });

  testWidgets('真实关注操作：人物资料关注态', (tester) async {
    final session = await startJourney(tester, 'player');
    await tester.tap(find.byTooltip('关注陪练'));
    await tester.pumpAndSettle();
    expect(session.repo.following, contains(session.repo.players.first['id']));
    expect(find.byTooltip('取消关注'), findsOneWidget);
    await captureJourney(tester, session.key, 'player_followed');
    await tester.tap(find.text('预约 TA'));
    await tester.pumpAndSettle();
    expect(find.text('选择游戏服务'), findsOneWidget);
    await captureJourney(tester, session.key, 'player_booking_sheet');
    await finishJourney(tester);
  });

  testWidgets('真实预约操作：选人、规格、时段、核对、取消与订单筛选', (tester) async {
    final session = await startJourney(tester, 'booking');
    await tester.tap(find.text('选择意向队友'));
    await tester.pumpAndSettle();
    expect(find.text('阿屿'), findsOneWidget);
    await captureJourney(tester, session.key, 'booking_player_sheet');

    await tester.tap(find.text('阿屿'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'PC · 120分钟 · ¥72'));
    await tester.pumpAndSettle();
    expect(find.text('¥72'), findsOneWidget);
    await captureJourney(tester, session.key, 'booking_selected_variant');

    await reveal(tester, find.text('14:00'));
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    await captureJourney(tester, session.key, 'booking_today_slot');

    await reveal(tester, find.byType(TextFormField).first);
    await tester.enterText(
      find.byType(TextFormField).first,
      'demo@example.com',
    );
    await reveal(tester, find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, '想练习路线沟通和报点配合');
    await captureJourney(tester, session.key, 'booking_contact_filled');

    await tester.tap(find.text('核对预约'));
    await tester.pumpAndSettle();
    expect(find.text('核对这次预约'), findsOneWidget);
    expect(find.text('120 分钟'), findsOneWidget);
    await captureJourney(tester, session.key, 'booking_review_ready');

    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(session.repo.orders, isEmpty);
    await reveal(tester, find.text('请先阅读并同意预约说明'));
    await captureJourney(tester, session.key, 'booking_consent_needed');

    await reveal(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(session.repo.orders, hasLength(1));
    expect(
      session.repo.orders.single['serviceSnapshot']['variantId'],
      'pc-120',
    );
    expect(
      session.repo.orders.single['fulfillmentStatus'],
      'awaiting_assignment',
    );
    await captureJourney(tester, session.key, 'order_created');

    await tester.scrollUntilVisible(
      find.text('取消预约'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('取消预约'));
    await tester.pumpAndSettle();
    expect(find.text('确认取消'), findsOneWidget);
    await captureJourney(tester, session.key, 'order_cancel_confirm');

    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();
    expect(session.repo.orders.single['status'], 'cancelled');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('订单').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('已结束'));
    await tester.pumpAndSettle();
    expect(find.text('预约已取消'), findsOneWidget);
    await captureJourney(tester, session.key, 'orders_finished');

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('三角洲 · PC 小时陪'), findsOneWidget);
    await finishJourney(tester);
  });
}
