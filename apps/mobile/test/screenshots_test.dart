import 'capture_2x.dart';
import 'catalog_media_cache.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/screens.dart';

const memberScreens = [
  'member',
  'member_orders',
  'member_order',
  'delivery',
  'availability',
  'earnings',
  'member_notifications',
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final screen in screenNames.where(
    (s) => ![
      'home',
      'service',
      'player',
      'order',
      ...stateScreenNames,
    ].contains(s),
  )) {
    testWidgets('working iOS gallery: $screen', (tester) async {
      enableCaptureShadows();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ClubRepository(
        persist: false,
        clock: () => DateTime.utc(2026, 11, 15, 10, 30),
      );
      await repo.load();
      expect(repo.error, isNull);
      // Both fixtures are exported by the API's authenticated state-machine flows.
      // The offline member preview is explicitly read-only; no fake write success.
      await repo.loadDemoPreview();
      if (memberScreens.contains(screen)) await repo.loadMemberData();
      await tester.runAsync(primeCatalogMedia);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OpenNIApp(repository: repo, initialScreen: screen),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => primeLocalMedia(tester.element(find.byType(Scaffold).first)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$screen must render without overflow',
      );
      await expectLater(
        await captureAt2x(key),
        matchesGoldenFile('../screenshots/$screen.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
