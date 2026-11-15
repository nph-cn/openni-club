import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/device_preview.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

void main() {
  testWidgets('预览使用固定逻辑安全区，桌面居中缩放，真机默认无设备壳', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ClubRepository(persist: false);
    await repo.load();
    await tester.pumpWidget(OpenNIApp(repository: repo, previewDevice: true));
    await tester.pumpAndSettle();
    expect(find.byType(IPhonePreview), findsOneWidget);
    expect(find.text('9:41'), findsOneWidget);
    final scaffold = tester.element(find.byType(Scaffold).first);
    expect(MediaQuery.sizeOf(scaffold), IPhonePreview.logicalSize);
    expect(MediaQuery.viewPaddingOf(scaffold), IPhonePreview.safeArea);
    final rect = tester.getRect(find.byType(Scaffold).first);
    expect(rect.center.dx, 640);
    expect(rect.center.dy, 450);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      OpenNIApp(key: const ValueKey('native'), repository: repo),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IPhonePreview), findsNothing);
    expect(find.text('9:41'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('个人中心关注卡打开实际关注目录并支持空状态', (tester) async {
    final repo = ClubRepository(persist: false);
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'profile'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('本机关注'));
    await tester.pumpAndSettle();
    expect(find.text('俱乐部陪练'), findsOneWidget);
    expect(find.text('本机关注'), findsOneWidget);
    expect(find.text('还没有本机关注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('退出只结束当前会话，保留演示预约与本机关注', () async {
    final repo = ClubRepository(persist: false);
    await repo.load();
    repo.token = 'test-session';
    repo.role = 'member';
    repo.orders = [
      {'id': 'retained'},
    ];
    repo.following.add('p1');
    repo.memberOrders = [
      {'id': 'private-member-order'},
    ];
    await repo.signOut();
    expect(repo.token, isNull);
    expect(repo.role, 'customer');
    expect(repo.memberOrders, isEmpty);
    expect(repo.orders.single['id'], 'retained');
    expect(repo.following, contains('p1'));
  });

  test('本地排班缓存会随当前时间重新过滤', () async {
    var clock = DateTime.utc(2026, 11, 16, 5);
    final repo = ClubRepository(persist: false, clock: () => clock);
    final day = DateTime(2026, 11, 16);
    expect((await repo.getAvailability('p1', day, 60)).length, 4);
    clock = DateTime.utc(2026, 11, 16, 10, 30);
    final slots = await repo.getAvailability('p1', day, 60);
    expect(slots.length, 1);
    expect(slots.single['startAt'], '2026-11-16T12:00:00.000Z');
  });
}
