import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/accessibility.dart';
import 'package:openni_club/loading.dart';
import 'package:openni_club/ui.dart';

Widget loadingHost({
  MediaQueryData media = const MediaQueryData(),
  bool tickerEnabled = true,
  Widget child = const ClubSkeleton(kind: SkeletonKind.slots),
}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TickerMode(enabled: tickerEnabled, child: child),
  ),
);

Finder get pulseFade => find.descendant(
  of: find.byType(SkeletonPulse),
  matching: find.byType(FadeTransition),
);

double opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(pulseFade).opacity.value;

void main() {
  testWidgets(
    'skeleton has one loading live region and excludes decorative content',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        loadingHost(
          media: const MediaQueryData(reduceMotion: true),
          child: const SkeletonPulse(
            child: Column(
              children: [
                Text('decorative content'),
                SkeletonBlock(width: 120, height: 20),
                SkeletonBlock(width: 80, height: 20),
              ],
            ),
          ),
        ),
      );
      final announcement = find.bySemanticsLabel('正在加载');
      expect(announcement, findsOneWidget);
      expect(
        tester.getSemantics(announcement),
        isSemantics(label: '正在加载', isLiveRegion: true),
      );
      expect(find.bySemanticsLabel('decorative content'), findsNothing);
      expect(find.byType(FadeTransition), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one shared pulse animates and stops when TickerMode is disabled',
    (tester) async {
      await tester.pumpWidget(loadingHost());
      expect(find.byType(SkeletonBlock), findsNWidgets(6));
      expect(pulseFade, findsOneWidget);
      final initial = opacity(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(opacity(tester), isNot(initial));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(loadingHost(tickerEnabled: false));
      expect(opacity(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(opacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  final preferences = <String, MediaQueryData>{
    'Reduce Motion': const MediaQueryData(reduceMotion: true),
    'Disable Animations': const MediaQueryData(disableAnimations: true),
    'High Contrast': const MediaQueryData(highContrast: true),
  };
  for (final preference in preferences.entries) {
    testWidgets('${preference.key} stops an active skeleton pulse', (
      tester,
    ) async {
      await tester.pumpWidget(loadingHost());
      await tester.pump(const Duration(milliseconds: 350));
      expect(opacity(tester), lessThan(1));
      await tester.pumpWidget(loadingHost(media: preference.value));
      expect(opacity(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(opacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('all skeleton layouts fit the mobile page width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final kind in SkeletonKind.values) {
      await tester.pumpWidget(
        loadingHost(
          media: const MediaQueryData(size: Size(390, 844), reduceMotion: true),
          child: ClubSkeleton(kind: kind),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'Layout: ${kind.name}');
      expect(find.byType(SkeletonPulse), findsOneWidget);
      expect(pulseFade, findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Android uses solid glass while iOS blur follows accessibility settings',
    (tester) async {
      final originalTransparency = GlassPreferences.reduceTransparency.value;
      GlassPreferences.reduceTransparency.value = false;
      addTearDown(
        () => GlassPreferences.reduceTransparency.value = originalTransparency,
      );
      Widget glassApp(TargetPlatform platform, {bool reduceMotion = false}) =>
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(reduceMotion: reduceMotion),
              child: const GlassSurface(
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          );

      await tester.pumpWidget(glassApp(TargetPlatform.android));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(glassApp(TargetPlatform.iOS));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pumpWidget(glassApp(TargetPlatform.iOS, reduceMotion: true));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
