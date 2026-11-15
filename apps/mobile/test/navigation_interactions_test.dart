import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

void main() {
  testWidgets('大屏底栏与内容同宽居中，手机底栏宽度保持不变', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ClubRepository(persist: false);
    await repo.load();
    for (final width in [390.0, 1281.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(OpenNIApp(repository: repo));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(ClubTabBar));
      expect(rect.width, (width > 620 ? 620 : width) - 32);
      expect(rect.center.dx, width / 2);
      expect(tester.takeException(), isNull);
      final inset = width > 620 ? (width - 620) / 2 : 0.0;
      await tester.pumpWidget(
        OpenNIApp(
          key: ValueKey('services-$width'),
          repository: repo,
          initialScreen: 'services',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('找服务')).dx, inset + 22);
      await tester.pumpWidget(
        OpenNIApp(
          key: ValueKey('service-$width'),
          repository: repo,
          initialScreen: 'service',
        ),
      );
      await tester.pumpAndSettle();
      final actionBar = find.ancestor(
        of: find.text('立即预约'),
        matching: find.byType(GlassSurface),
      );
      expect(tester.getSize(actionBar).width, (width > 620 ? 620 : width) - 32);
      expect(tester.getCenter(actionBar).dx, width / 2);
      expect(
        tester.getTopLeft(find.byTooltip('返回')).dx,
        greaterThanOrEqualTo(inset),
      );
      expect(tester.getCenter(find.text('服务详情')).dx, width / 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('搜索清除后恢复真实目录，浮动导航可以返回首页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ClubRepository(persist: false);
    await repo.load();
    await tester.pumpWidget(
      OpenNIApp(repository: repo, initialScreen: 'services'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的服务');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.byTooltip('首页'));
    await tester.pumpAndSettle();
    expect(find.text(repo.clubName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横幅计数按钮切换真实配置并遵守减少动态设置', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          reduceMotion: true,
          disableAnimations: true,
        );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = ClubRepository(persist: false);
    await repo.load();
    repo.banners = [
      {'id': 'one', 'title': '第一张配置横幅', 'game': '三角洲行动', 'imageUrl': ''},
      {'id': 'two', 'title': '第二张配置横幅', 'game': '无畏契约', 'imageUrl': ''},
    ];
    await tester.pumpWidget(OpenNIApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一张横幅'));
    await tester.pumpAndSettle();
    expect(find.text('第二张配置横幅'), findsOneWidget);
    expect(find.bySemanticsLabel('下一张横幅，当前第 2 张，共 2 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
