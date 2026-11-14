import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

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
  for (final screen in ['home', 'service', 'player', 'order']) {
    testWidgets('v2 review: $screen', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ClubRepository(
        persist: false,
        clock: () => DateTime(2026, 11, 15, 18, 30),
      );
      await repo.load();
      // Exported from the API's real create -> assign -> accept -> start flow.
      repo.orders = [
        Json.from(
          jsonDecode(
            await rootBundle.loadString(
              'assets/demo/order-in-progress.json',
              cache: false,
            ),
          ),
        ),
      ];
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OpenNIApp(repository: repo, initialScreen: screen),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$screen must have no overflow',
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('../screenshots/$screen.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
