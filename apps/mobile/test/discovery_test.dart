import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/booking.dart';
import 'package:openni_club/discover.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

Future<ClubRepository> openDirectory(
  WidgetTester tester, {
  String screen = 'services',
  ClubRepository? repository,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo =
      repository ??
      ClubRepository(
        persist: false,
        clock: () => DateTime.utc(2026, 11, 16, 5),
      );
  await repo.load();
  await tester.pumpWidget(OpenNIApp(repository: repo, initialScreen: screen));
  await tester.pumpAndSettle();
  return repo;
}

List<String> shownPlayers(WidgetTester tester) => tester
    .widgetList<RosterRow>(find.byType(RosterRow))
    .map((row) => '${row.player['id']}')
    .toList();

Future<void> chooseSection(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('服务与陪练分段保留各自搜索，陪练搜索忽略空格和大小写', (tester) async {
    await openDirectory(tester);
    await tester.enterText(find.byType(EditableText), '复盘');
    await tester.pumpAndSettle();
    expect(find.text('三角洲 · 对局复盘'), findsOneWidget);
    await chooseSection(tester, '俱乐部陪练');
    await tester.enterText(find.byType(EditableText), '  eChO  ');
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p2']);
    await chooseSection(tester, '游戏服务');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '复盘',
    );
    expect(find.text('三角洲 · 对局复盘'), findsOneWidget);
    await chooseSection(tester, '俱乐部陪练');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '  eChO  ',
    );
    expect(shownPlayers(tester), ['p2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('陪练按角色和游戏搜索，游戏条件与关键词共同过滤并可清除', (tester) async {
    await openDirectory(tester, screen: 'players');
    await tester.enterText(find.byType(EditableText), '指挥');
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p1']);
    await tester.enterText(find.byType(EditableText), '英雄联盟');
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p3', 'p4']);
    final deltaChip = find.widgetWithText(ChoiceChip, '三角洲行动');
    await tester.ensureVisible(deltaChip);
    await tester.tap(deltaChip);
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p4']);
    await tester.enterText(find.byType(EditableText), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的陪练'), findsOneWidget);
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p1', 'p2', 'p3', 'p4']);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('游戏深链同步约束两个目录，独立陪练页保留返回入口', (tester) async {
    await openDirectory(tester);
    final router = GoRouter.of(tester.element(find.byType(ServicesPage)));
    router.go('/services?game=${Uri.encodeComponent('无畏契约')}');
    await tester.pumpAndSettle();
    expect(find.text('无畏契约 · 组队小时陪'), findsOneWidget);
    expect(find.text('三角洲 · PC 小时陪'), findsNothing);
    await chooseSection(tester, '俱乐部陪练');
    expect(shownPlayers(tester), ['p2', 'p3']);
    router.push('/players?game=${Uri.encodeComponent('英雄联盟')}');
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p3', 'p4']);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(ClubTabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本机关注目录随取消关注更新，空态可回到全部陪练', (tester) async {
    final repo = ClubRepository(persist: false);
    repo.following.add('p2');
    await openDirectory(tester, screen: 'following', repository: repo);
    expect(
      tester.widget<PlayersPage>(find.byType(PlayersPage)).onlyFollowing,
      isTrue,
    );
    expect(shownPlayers(tester), ['p2']);
    await repo.toggleFollow('p2');
    await tester.pumpAndSettle();
    expect(find.text('还没有本机关注'), findsOneWidget);
    await tester.tap(find.text('查看全部陪练'));
    await tester.pumpAndSettle();
    expect(shownPlayers(tester), ['p1', 'p2', 'p3', 'p4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择120分钟后经陪练主页预约，保留服务规格和陪练', (tester) async {
    await openDirectory(tester, screen: 'service');
    await tester.ensureVisible(find.text('PC · 120分钟'));
    await tester.tap(find.text('PC · 120分钟'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('阿屿'));
    await tester.tap(find.text('阿屿'));
    await tester.pumpAndSettle();
    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.serviceId, 's1');
    expect(player.variantId, 'pc-120');
    expect(player.id, 'p1');
    expect(find.textContaining('¥72', findRichText: true), findsWidgets);
    await tester.tap(find.text('预约 TA'));
    await tester.pumpAndSettle();
    final booking = tester.widget<BookingPage>(find.byType(BookingPage));
    expect(booking.serviceId, 's1');
    expect(booking.variantId, 'pc-120');
    expect(booking.playerId, 'p1');
    expect(find.text('选择游戏服务'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从陪练服务卡进入详情再预约，仍指定该陪练和所选规格', (tester) async {
    await openDirectory(tester, screen: 'player');
    await tester.ensureVisible(find.text('三角洲 · PC 小时陪'));
    await tester.tap(find.text('三角洲 · PC 小时陪'));
    await tester.pumpAndSettle();
    expect(tester.widget<ServicePage>(find.byType(ServicePage)).playerId, 'p1');
    await tester.ensureVisible(find.text('PC · 120分钟'));
    await tester.tap(find.text('PC · 120分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即预约'));
    await tester.pumpAndSettle();
    final booking = tester.widget<BookingPage>(find.byType(BookingPage));
    expect(booking.serviceId, 's1');
    expect(booking.variantId, 'pc-120');
    expect(booking.playerId, 'p1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立访问陪练先选服务，能预约非首项而不静默默认', (tester) async {
    await openDirectory(tester, screen: 'player');
    await tester.tap(find.text('预约 TA'));
    await tester.pumpAndSettle();
    expect(find.text('选择游戏服务'), findsOneWidget);
    expect(find.byType(BookingPage), findsNothing);
    final secondService = find.widgetWithText(ListTile, '三角洲 · 对局复盘');
    await tester.ensureVisible(secondService);
    await tester.tap(secondService);
    await tester.pumpAndSettle();
    final booking = tester.widget<BookingPage>(find.byType(BookingPage));
    expect(booking.serviceId, 's2');
    expect(booking.playerId, 'p1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('失效的服务规格不会沿用错误价格，预约前重新选择', (tester) async {
    await openDirectory(tester, screen: 'player');
    GoRouter.of(tester.element(find.byType(PlayerPage)))
        .go('/players/p1?service=s1&variant=removed');
    await tester.pumpAndSettle();
    expect(find.text('原服务或规格已不可用，请重新选择。'), findsOneWidget);
    await tester.tap(find.text('预约 TA'));
    await tester.pumpAndSettle();
    expect(find.text('选择游戏服务'), findsOneWidget);
    expect(find.byType(BookingPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
