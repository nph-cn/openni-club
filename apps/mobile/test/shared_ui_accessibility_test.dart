import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/accessibility.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  late ClubRepository repo;
  setUp(() async {
    repo = ClubRepository(persist: false);
    await repo.load();
  });

  Widget host(Widget child, {double scale = 1, bool highContrast = false}) =>
      MaterialApp(
        theme: clubTheme(
          repo,
          previewFonts: true,
        ).copyWith(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 568),
            textScaler: TextScaler.linear(scale),
            highContrast: highContrast,
          ),
          child: child,
        ),
      );

  testWidgets('底部导航只宣读一次名称并暴露选中状态', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(Scaffold(body: ClubTabBar(repo: repo, selected: 0))),
    );
    final home = find.bySemanticsLabel('首页');
    expect(home, findsOneWidget);
    expect(
      tester.getSemantics(home),
      matchesSemantics(
        label: '首页',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(find.bySemanticsLabel(RegExp('首页.*首页')), findsNothing);
    expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('小屏大字体完整显示信息，最后一项避开实际浮动底栏', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [2.0, 3.0]) {
      await tester.pumpWidget(
        host(
          ClubPage(
            repo: repo,
            tab: 1,
            title: '找服务',
            child: PageList(
              children: [
                const PairRow('预约时间', '11月16日 14:00'),
                const PairRow('联系信息', 'example-long-contact'),
                for (var i = 0; i < 12; i++) Text('服务内容 $i'),
                const Text('最后一项', key: ValueKey('last-item')),
              ],
            ),
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale 倍字号初始布局');
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale 倍字号滚动布局');
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('last-item'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(ClubTabBar)).dy),
      );
    }
  });

  testWidgets('苹果搜索清除有44点触区，提交收起焦点并保留回调', (tester) async {
    final controller = TextEditingController(text: '三角洲');
    addTearDown(controller.dispose);
    String? query, submitted;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ClubSearchField(
              controller: controller,
              onChanged: (value) => query = value,
              onSubmitted: (value) => submitted = value,
            ),
          ),
        ),
        scale: 2,
      ),
    );
    final clear = find.byTooltip('清除搜索');
    expect(tester.getSize(clear).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
    await tester.tap(clear);
    await tester.pump();
    expect(query, '');
    expect(controller.text, isEmpty);
    await tester.enterText(find.byType(EditableText), '复盘');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, '复盘');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('品牌图保持完整比例，实色无透明模式不建立模糊层', (tester) async {
    final old = GlassPreferences.reduceTransparency.value;
    addTearDown(() => GlassPreferences.reduceTransparency.value = old);
    await tester.pumpWidget(host(Scaffold(body: BrandMark(repo))));
    expect(
      tester
          .widget<Image>(
            find.descendant(
              of: find.byType(BrandMark),
              matching: find.byType(Image),
            ),
          )
          .fit,
      BoxFit.contain,
    );
    for (final reduced in [false, true]) {
      GlassPreferences.reduceTransparency.value = reduced;
      await tester.pumpWidget(
        host(const GlassSurface(child: SizedBox(width: 100, height: 100))),
      );
      expect(
        find.byType(BackdropFilter),
        reduced ? findsNothing : findsOneWidget,
      );
    }
    GlassPreferences.reduceTransparency.value = false;
    await tester.pumpWidget(
      host(
        const GlassSurface(child: SizedBox(width: 100, height: 100)),
        highContrast: true,
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('预览的标题与按钮真正使用已加载字体，原生不强制Noto', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          appBar: AppBar(title: const Text('导航标题')),
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('主要操作')),
              OutlinedButton(onPressed: () {}, child: const Text('次要操作')),
              TextButton(onPressed: () {}, child: const Text('文字操作')),
              const Chip(label: Text('游戏选项')),
              const ListTile(title: Text('列表标题'), subtitle: Text('列表说明')),
            ],
          ),
        ),
      ),
    );
    for (final label in [
      '导航标题',
      '主要操作',
      '次要操作',
      '文字操作',
      '游戏选项',
      '列表标题',
      '列表说明',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.text.style?.fontFamily, 'NotoSansSC', reason: label);
    }
    final native = clubTheme(repo);
    expect(native.appBarTheme.titleTextStyle?.fontFamily, isNull);
    expect(
      native.filledButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      isNull,
    );
  });
}
