import 'capture_2x.dart';
import 'catalog_media_cache.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';

/// 长页面的下半屏与后续内容段。截图仍是实际运行的控件树，
/// 只按固定滚动距离分段，便于图库像 Mobbin 一样覆盖整个页面长度。
const sections = <String, List<(String, double)>>{
  'home': [('home_sections_services', -520), ('home_sections_more', -1060)],
  'services': [('services_sections_more', -520), ('services_sections_filters', -260)],
  'service': [('service_sections_rules', -600), ('service_sections_reviews', -1100)],
  'players': [('players_sections_more', -520), ('players_sections_profiles', -900)],
  'player': [('player_sections_booking', -620), ('player_sections_reviews', -1100)],
  'booking': [('booking_sections_time', -500), ('booking_sections_confirm', -900)],
  'checkout': [('checkout_sections_terms', -440), ('checkout_sections_summary', -820)],
  'orders': [('orders_sections_more', -520), ('orders_sections_finished', -1000)],
  'order': [('order_sections_events', -560), ('order_sections_timeline', -1000)],
  'support': [('support_sections_more', -420)],
  'profile': [('profile_sections_more', -560), ('profile_sections_settings', -1000)],
  'announcements': [('announcements_sections_more', -420)],
  'settings': [('settings_sections_more', -480), ('settings_sections_account', -900)],
  'notifications': [('notifications_sections_more', -320)],
  'following': [('following_sections_more', -400)],
  'member': [('member_sections_work', -520), ('member_sections_more', -1040), ('member_sections_earnings', -1560)],
  'member_orders': [('member_orders_sections_more', -520)],
  'member_order': [('member_order_sections_more', -520)],
  'earnings': [('earnings_sections_more', -520), ('earnings_sections_settlement', -980)],
  'availability': [('availability_sections_more', -400)],
  'delivery': [('delivery_sections_more', -520)],
  'member_notifications': [('member_notifications_sections_more', -400)],
  'home_android': [('home_android_sections_more', -560)],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCaptureFonts);
  for (final entry in sections.entries) {
    final screen = entry.key;
    for (final (id, offset) in entry.value) {
      testWidgets('page sections: $id', (tester) async {
        enableCaptureShadows();
        debugDefaultTargetPlatformOverride = screen == 'home_android'
            ? TargetPlatform.android
            : TargetPlatform.iOS;
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
        await repo.loadDemoPreview();
        final memberScreens = ['member', 'member_orders', 'member_order', 'delivery', 'availability', 'earnings', 'member_notifications'];
        if (memberScreens.contains(screen)) await repo.loadMemberData();
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
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isEmpty) {
          await tester.pumpWidget(const SizedBox.shrink());
          return;
        }
        await tester.drag(scrollables.first, Offset(0, offset), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$id must have no overflow');
        await expectLater(
          await captureAt2x(key),
          matchesGoldenFile('../screenshots/$id.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
