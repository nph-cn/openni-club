import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoIcons,
        CupertinoSearchTextField,
        CupertinoSlidingSegmentedControl,
        OverlayVisibilityMode;

import 'repository.dart';
import 'accessibility.dart';

// ---------------------------------------------------------------------------
// Palette. Cool near-white canvas, a graphite ink, a single quiet accent.
// ---------------------------------------------------------------------------
const canvas = Color(0xFFF4F5F7),
    ink = Color(0xFF14181E),
    muted = Color(0xFF6C7480),
    faint = Color(0xFF9AA1AB),
    rule = Color(0xFFE5E8ED),
    sage = Color(0xFFEDF0F4),
    sand = Color(0xFFF2F0EB),
    forest = Color(0xFF232A33),
    positive = Color(0xFF1F7A54),
    warning = Color(0xFF8A6218),
    danger = Color(0xFFB33B32),
    link = Color(0xFF2F5BD7);

Color brandColor(ClubRepository repo) {
  final hex = '${repo.club['primaryColor'] ?? '#272D35'}'.replaceFirst('#', '');
  return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF272D35);
}

Color onBrand(ClubRepository repo) =>
    brandColor(repo).computeLuminance() > .18 ? ink : Colors.white;

String money(Json item, [String field = 'priceCents']) {
  final cents = item[field] as num? ?? 0;
  return (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2);
}

String when(dynamic value, {bool onlyTime = false}) {
  final time = DateTime.tryParse('$value')
      ?.toUtc()
      .add(const Duration(hours: 8));
  if (time == null) return '待安排';
  final hm =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  return onlyTime ? hm : '${time.month}月${time.day}日 $hm';
}

String stage(Json o) =>
    '${o['fulfillmentStatus'] ?? (o['status'] == 'cancelled' ? 'cancelled' : 'awaiting_assignment')}';

/// 优先使用下单时冻结的规格，目录后续改价不会改变历史订单。
String orderSpecification(Json order) {
  final snapshot = order['serviceSnapshot'] as Map? ?? const {};
  final title = '${snapshot['variantTitle'] ?? ''}'.trim();
  final minutes = snapshot['durationMinutes'] ?? order['durationMinutes'];
  if (title.isNotEmpty) {
    return minutes != null && !title.contains('$minutes')
        ? '$title · $minutes分钟'
        : title;
  }
  return [
    if ('${snapshot['platform'] ?? ''}'.isNotEmpty) '${snapshot['platform']}',
    if (minutes != null) '$minutes分钟',
  ].join(' · ');
}

String stageName(String value) =>
    const {
      'awaiting_payment': '待付款',
      'awaiting_assignment': '等待俱乐部派单',
      'awaiting_acceptance': '等待队友接单',
      'scheduled': '已安排，等待开始',
      'in_progress': '服务进行中',
      'awaiting_confirmation': '等待你确认完成',
      'disputed': '售后处理中',
      'completed': '服务已完成',
      'cancelled': '预约已取消',
    }[value] ??
    '等待更新';

void toast(BuildContext context, Object text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text('$text'.replaceFirst('Exception: ', ''))),
    );

// ---------------------------------------------------------------------------
// Type scale: a tight iOS-like ramp in a 390pt viewport.
// Page 24 · Detail title 22 · Section 17 · Body 15 · Secondary 12 · Caption 11.
// Numerals are tabular so prices, times and counts stay optically aligned.
// ---------------------------------------------------------------------------
final _tabular = FontFeature.tabularFigures();

const typePage = TextStyle(
  fontSize: 24,
  height: 1.16,
  fontWeight: FontWeight.w700,
  letterSpacing: -.6,
  color: ink,
);
const typeTitle = TextStyle(
  fontSize: 22,
  height: 1.24,
  fontWeight: FontWeight.w700,
  letterSpacing: -.5,
  color: ink,
);
const typeSection = TextStyle(
  fontSize: 17,
  height: 1.28,
  fontWeight: FontWeight.w600,
  letterSpacing: -.25,
  color: ink,
);
const typeBody = TextStyle(fontSize: 15, height: 1.45, color: ink);
const typeBodySmall = TextStyle(fontSize: 14, height: 1.4, color: ink);
const typeSecondary = TextStyle(fontSize: 12, height: 1.4, color: muted);
const typeCaption = TextStyle(fontSize: 11, height: 1.35, color: faint);
const typeLabel = TextStyle(
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w600,
  color: ink,
);
final typePrice = TextStyle(
  fontSize: 19,
  height: 1.1,
  fontWeight: FontWeight.w700,
  letterSpacing: -.4,
  color: ink,
  fontFeatures: [_tabular],
);
final typeNumber = TextStyle(
  fontSize: 15,
  height: 1.2,
  fontWeight: FontWeight.w600,
  color: ink,
  fontFeatures: [_tabular],
);
final typeNumberLarge = TextStyle(
  fontSize: 26,
  height: 1.05,
  fontWeight: FontWeight.w700,
  letterSpacing: -.6,
  color: ink,
  fontFeatures: [_tabular],
);

/// iOS-style status colours for fulfillment states, never for invented data.
Color stageTone(String value) => switch (value) {
  'in_progress' => const Color(0xFF2B5BD7),
  'scheduled' => const Color(0xFF5A5FCE),
  'awaiting_confirmation' => const Color(0xFF8A6218),
  'disputed' => danger,
  'completed' => positive,
  'cancelled' => muted,
  _ => const Color(0xFF4C5563),
};

Color stageFill(String value) => switch (value) {
  'in_progress' => const Color(0xFFE7EEFC),
  'scheduled' => const Color(0xFFECECFA),
  'awaiting_confirmation' => const Color(0xFFF7F0DE),
  'disputed' => const Color(0xFFF9E9E7),
  'completed' => const Color(0xFFE7F2EC),
  'cancelled' => const Color(0xFFEDEFF2),
  _ => const Color(0xFFEDF0F4),
};

Color playerTint(Json player) {
  final hex = '${player['color'] ?? '#2455E7'}'.replaceFirst('#', '');
  return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF2455E7);
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------
ThemeData clubTheme(ClubRepository repo, {bool previewFonts = false}) {
  final fontFamily = kIsWeb || previewFonts ? 'NotoSansSC' : null;
  final brand = brandColor(repo);
  return ThemeData(
    useMaterial3: true,
    platform: kIsWeb ? TargetPlatform.iOS : defaultTargetPlatform,
    fontFamily: fontFamily,
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      primary: brand,
      onPrimary: onBrand(repo),
      surface: Colors.white,
      onSurface: ink,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        height: 1.24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
      labelLarge: TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, height: 1.2, color: muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 17,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: ink,
      ),
    ),
    iconTheme: const IconThemeData(color: ink, size: 20),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: brand,
      checkmarkColor: onBrand(repo),
      secondaryLabelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        color: onBrand(repo),
      ),
      labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, color: ink),
      side: const BorderSide(color: rule, width: .5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    dividerTheme: const DividerThemeData(color: rule, space: 20, thickness: .5),
    listTileTheme: ListTileThemeData(
      minTileHeight: 52,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        height: 1.3,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        height: 1.4,
        color: muted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: Colors.white,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        backgroundColor: Colors.white.withValues(alpha: .65),
        side: const BorderSide(color: rule, width: .6),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 40),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        color: muted,
      ),
      hintStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: faint,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: rule, width: .6),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: brand, width: 1.4),
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    ),
  );
}

bool appleChrome(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

// ---------------------------------------------------------------------------
// Glass material used by navigation, transaction bars and sheets.
// ---------------------------------------------------------------------------
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 22,
    this.border = true,
  });
  final Widget child;
  final double radius;
  final bool border;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: GlassPreferences.reduceTransparency,
    builder: (context, reduced, _) {
      final media = MediaQuery.of(context);
      final opaque =
          reduced ||
          media.highContrast ||
          media.disableAnimations ||
          media.reduceMotion ||
          !appleChrome(context);
      final surface = DecoratedBox(
        decoration: BoxDecoration(
          color: opaque ? const Color(0xFFF8F9FB) : null,
          gradient: opaque
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xD6FFFFFF),
                    Color(0xA8F1F4F9),
                    Color(0xC4FFFFFF),
                  ],
                  stops: [0, .55, 1],
                ),
          borderRadius: BorderRadius.circular(radius),
          border: border
              ? Border.all(
                  color: opaque ? rule : Colors.white.withValues(alpha: .55),
                  width: .8,
                )
              : null,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: opaque
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: CustomPaint(
                  foregroundPainter: border ? _GlassEdgePainter(radius) : null,
                  child: surface,
                ),
              ),
      );
    },
  );
}

/// 单次描边增强材质边缘；不会给正文添加模糊或动画。
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0x36FFFFFF), Color(0xA8FFFFFF)],
        stops: [0, .52, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      radius != oldDelegate.radius;
}

/// 独立浮动导航：选中态覆盖完整触控区域，文字和价格不叠加模糊。
class ClubTabBar extends StatelessWidget {
  const ClubTabBar({super.key, required this.repo, required this.selected});
  final ClubRepository repo;
  final int selected;
  @override
  Widget build(BuildContext context) {
    final member = repo.role == 'member';
    final labels = member
        ? ['工作台', '订单', '收入', '我的']
        : ['首页', '找陪练', '订单', '我的'];
    final icons = member
        ? [
            CupertinoIcons.square_grid_2x2,
            CupertinoIcons.doc_text,
            CupertinoIcons.creditcard,
            CupertinoIcons.person,
          ]
        : [
            CupertinoIcons.house,
            CupertinoIcons.search,
            CupertinoIcons.doc_text,
            CupertinoIcons.person,
          ];
    final selectedIcons = member
        ? [
            CupertinoIcons.square_grid_2x2_fill,
            CupertinoIcons.doc_text_fill,
            CupertinoIcons.creditcard_fill,
            CupertinoIcons.person_fill,
          ]
        : [
            CupertinoIcons.house_fill,
            CupertinoIcons.search,
            CupertinoIcons.doc_text_fill,
            CupertinoIcons.person_fill,
          ];
    final paths = member
        ? ['/member', '/member/orders', '/member/earnings', '/profile']
        : ['/', '/services', '/orders', '/profile'];
    final media = MediaQuery.of(context);
    final duration = media.disableAnimations || media.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 190);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: selected == i,
                button: true,
                label: labels[i],
                child: Tooltip(
                  message: labels[i],
                  excludeFromSemantics: true,
                  child: InkWell(
                    onTap: () {
                      if (selected != i) context.go(paths[i]);
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: 7,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: selected == i
                            ? Colors.white.withValues(alpha: .95)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected == i
                              ? Colors.white
                              : Colors.transparent,
                        ),
                        boxShadow: selected == i
                            ? [
                                BoxShadow(
                                  color: ink.withValues(alpha: .07),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected == i ? selectedIcons[i] : icons[i],
                              size: 22,
                              color: selected == i ? ink : muted,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                letterSpacing: .1,
                                fontWeight: selected == i
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected == i ? ink : muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 苹果平台使用搜索控件，清除按钮保留完整触区与键盘焦点。
class ClubSearchField extends StatelessWidget {
  const ClubSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = '搜索游戏或服务',
    this.onSubmitted,
    this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      void submit(String text) {
        FocusScope.of(context).unfocus();
        onSubmitted?.call(text);
      }

      void clear() {
        controller.clear();
        onChanged('');
        onClear?.call();
      }

      final hasText = value.text.isNotEmpty;
      final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
      if (!appleChrome(context)) {
        return TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: submit,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: hintText,
            suffixIcon: hasText
                ? IconButton(
                    tooltip: '清除搜索',
                    onPressed: clear,
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                  )
                : null,
          ),
        );
      }
      return Stack(
        alignment: Alignment.centerRight,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: CupertinoSearchTextField(
              controller: controller,
              placeholder: hintText,
              onChanged: onChanged,
              onSubmitted: submit,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 15,
                color: ink,
              ),
              placeholderStyle: TextStyle(
                fontFamily: fontFamily,
                fontSize: 15,
                color: faint,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: rule, width: .6),
              ),
              itemColor: muted,
              itemSize: 18,
              prefixInsets: const EdgeInsetsDirectional.fromSTEB(12, 0, 7, 0),
              padding: EdgeInsetsDirectional.fromSTEB(
                0,
                11,
                hasText ? 46 : 12,
                11,
              ),
              suffixMode: OverlayVisibilityMode.never,
            ),
          ),
          if (hasText)
            PositionedDirectional(
              end: 1,
              child: IconButton(
                tooltip: '清除搜索',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: clear,
                icon: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 18,
                  color: faint,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// 分组切换沿用平台控件的键盘、焦点和辅助功能语义。
class ClubSegmentedControl extends StatelessWidget {
  const ClubSegmentedControl({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
  });
  final List<String> values;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => appleChrome(context)
      ? CupertinoSlidingSegmentedControl<String>(
          groupValue: value,
          backgroundColor: const Color(0xFFE7EAEF),
          thumbColor: Colors.white,
          padding: const EdgeInsets.all(3),
          children: {
            for (final option in values)
              option: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 10,
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.fontFamily,
                    fontSize: 13,
                    height: 1.2,
                    letterSpacing: -.1,
                    fontWeight: value == option
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: value == option ? ink : muted,
                  ),
                ),
              ),
          },
          onValueChanged: (next) {
            if (next != null) onChanged(next);
          },
        )
      : Wrap(
          spacing: 8,
          children: [
            for (final option in values)
              ChoiceChip(
                label: Text(option),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              ),
          ],
        );
}

class _PageInsets extends InheritedWidget {
  const _PageInsets({
    required this.top,
    required this.bottom,
    required super.child,
  });
  final double top, bottom;
  static _PageInsets? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PageInsets>();
  @override
  bool updateShouldNotify(_PageInsets old) =>
      top != old.top || bottom != old.bottom;
}

class ClubPage extends StatelessWidget {
  const ClubPage({
    super.key,
    required this.repo,
    required this.child,
    this.title,
    this.tab,
    this.bottom,
    this.actions,
    this.appBar = true,
    this.onBack,
  });
  final ClubRepository repo;
  final Widget child;
  final String? title;
  final int? tab;
  final Widget? bottom;
  final List<Widget>? actions;
  final bool appBar;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final apple = appleChrome(context), media = MediaQuery.of(context);
    final toolbarHeight =
        (media.textScaler.scale(tab != null ? 24 : 17) * 1.2 + 14).clamp(
          48.0,
          double.infinity,
        );
    final chromeInset =
        (media.size.width - media.padding.horizontal - 640).clamp(
          0.0,
          double.infinity,
        ) /
        2;
    final showBar = tab != null || bottom != null;
    final nav = tab == null
        ? null
        : apple
        ? ClubTabBar(repo: repo, selected: tab!)
        : NavigationBar(
            selectedIndex: tab!,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            height: 60,
            animationDuration: media.disableAnimations || media.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            indicatorColor: brandColor(repo).withValues(alpha: .07),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: states.contains(WidgetState.selected) ? ink : muted,
              ),
            ),
            onDestinationSelected: (i) => context.go(
              (repo.role == 'member'
                  ? [
                      '/member',
                      '/member/orders',
                      '/member/earnings',
                      '/profile',
                    ]
                  : ['/', '/services', '/orders', '/profile'])[i],
            ),
            destinations: repo.role == 'member'
                ? const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: '工作台',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      label: '订单',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: '收入',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      label: '我的',
                    ),
                  ]
                : const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      label: '首页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      label: '找陪练',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: '订单',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      label: '我的',
                    ),
                  ],
          );
    final backButton = IconButton(
      tooltip: '返回',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .78),
        padding: const EdgeInsets.all(10),
      ),
      icon: Icon(
        apple ? CupertinoIcons.chevron_back : Icons.arrow_back_rounded,
        size: 18,
      ),
      onPressed:
          onBack ??
          () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
    );
    return Scaffold(
      extendBody: apple && showBar,
      extendBodyBehindAppBar: apple && appBar,
      appBar: !appBar
          ? null
          : AppBar(
              toolbarHeight: toolbarHeight,
              backgroundColor: apple ? Colors.transparent : canvas,
              scrolledUnderElevation: 0,
              centerTitle: tab == null,
              automaticallyImplyLeading: tab == null,
              leadingWidth: tab == null ? 54 + chromeInset : null,
              titleSpacing: tab != null ? 20 : null,
              title: Padding(
                padding: EdgeInsets.only(left: tab != null ? chromeInset : 0),
                child: Text(
                  title ?? '',
                  style: TextStyle(
                    fontSize: tab != null ? 24 : 17,
                    height: 1.15,
                    fontWeight: tab != null ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: tab != null ? -.5 : -.2,
                  ),
                ),
              ),
              flexibleSpace: apple
                  ? const GlassSurface(
                      radius: 0,
                      border: false,
                      child: SizedBox.expand(),
                    )
                  : null,
              leading: tab != null
                  ? null
                  : chromeInset > 0
                  ? Padding(
                      padding: EdgeInsets.only(left: chromeInset),
                      child: backButton,
                    )
                  : backButton,
              actions: [
                ...?actions,
                if (chromeInset > 0) SizedBox(width: chromeInset),
              ],
            ),
      body: Builder(
        builder: (bodyContext) => _PageInsets(
          // Scaffold 已提供真实导航高度，放大字号后也不会遮住最后一项。
          top: apple && appBar ? MediaQuery.paddingOf(bodyContext).top : 0,
          bottom: apple && showBar
              ? MediaQuery.paddingOf(bodyContext).bottom + 14
              : 0,
          child: SafeArea(
            top: !appBar,
            bottom: !apple,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: child,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: !showBar
          ? null
          : SafeArea(
              top: false,
              child: Center(
                heightFactor: 1,
                child: SizedBox(
                  width: 640,
                  child: Padding(
                    padding: apple
                        ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
                        : EdgeInsets.zero,
                    child: Container(
                      decoration: apple
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                bottom != null ? 24 : 30,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ink.withValues(alpha: .12),
                                  blurRadius: 26,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            )
                          : null,
                      child: GlassSurface(
                        radius: apple ? (bottom != null ? 24 : 30) : 0,
                        child: bottom != null
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: bottom!,
                              )
                            : nav!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class PageList extends StatelessWidget {
  const PageList({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 26),
    this.controller,
  });
  final ScrollController? controller;
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final inset = _PageInsets.of(context);
    return ListView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding:
          padding +
          EdgeInsets.only(top: inset?.top ?? 0, bottom: inset?.bottom ?? 0),
      children: children,
    );
  }
}

/// Quiet section heading: 17pt title with an optional 12pt caption and 13pt action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.caption,
    this.action,
    this.onTap,
    this.padding = const EdgeInsets.only(top: 18, bottom: 10),
  });
  final String title;
  final String? caption, action;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: typeSection),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(caption!, style: typeSecondary),
                ),
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: muted,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!, style: typeLabel),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Small inline label. 11pt, opaque fill or hairline outline.
class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.color = muted,
    this.fill = Colors.transparent,
    this.icon,
  });
  final String label;
  final Color color, fill;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      border: fill == Colors.transparent
          ? Border.all(color: rule, width: .6)
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: .1,
          ),
        ),
      ],
    ),
  );
}

Color colorFromHex(String? value, {Color fallback = muted}) {
  final hex = (value ?? '').replaceFirst('#', '').trim();
  if (hex.length != 6) return fallback;
  return Color(int.tryParse('FF$hex', radix: 16) ?? fallback.toARGB32());
}

/// 打手分级徽章。分级来自俱乐部实际配置，不根据价格或 UI 猜测。
class TierBadge extends StatelessWidget {
  const TierBadge({
    super.key,
    required this.tier,
    this.compact = false,
    this.showLevel = false,
  });
  final Json? tier;
  final bool compact, showLevel;
  @override
  Widget build(BuildContext context) {
    if (tier == null) return const SizedBox.shrink();
    final color = colorFromHex('${tier!['color']}', fallback: warning);
    final label = '${tier!['label'] ?? tier!['id']}';
    final level = tier!['level'];
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .32), width: .6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.military_tech_rounded, size: compact ? 10 : 12, color: color),
          const SizedBox(width: 3),
          Text(
            showLevel && level != null ? '$label · Lv$level' : label,
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: .1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 目录图片：同时支持官方 HTTPS 素材与仓库内本地演示图，失败时显示真实文字兜底。
class CatalogImage extends StatelessWidget {
  const CatalogImage(
    this.source, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallback,
    this.filterQuality = FilterQuality.medium,
  });
  final String source;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Widget? fallback;
  @override
  Widget build(BuildContext context) {
    final value = source.trim();
    if (value.startsWith('assets/')) {
      return Image.asset(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
      );
    }
    if (value.startsWith('https://')) {
      return Image.network(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
      );
    }
    return fallback ?? const SizedBox.shrink();
  }
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(14),
    this.border = false,
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: border ? rule : Colors.white.withValues(alpha: .9),
        width: .6,
      ),
      boxShadow: color == Colors.white
          ? [
              BoxShadow(
                color: ink.withValues(alpha: .03),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    ),
    child: child,
  );
}

/// Dense price label with tabular figures and an optional unit suffix.
class PriceText extends StatelessWidget {
  const PriceText(
    this.amount, {
    super.key,
    this.unit,
    this.size = 19,
    this.color = ink,
    this.prefix = '¥',
  });
  final String amount;
  final String? unit;
  final double size;
  final Color color;
  final String prefix;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$prefix$amount',
          style: TextStyle(
            fontSize: size,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
            color: color,
            fontFeatures: [_tabular],
          ),
        ),
        if (unit != null)
          TextSpan(
            text: unit,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: .58),
            ),
          ),
      ],
    ),
    textScaler: MediaQuery.textScalerOf(context),
  );
}

class PlayerArt extends StatelessWidget {
  const PlayerArt({
    super.key,
    required this.repo,
    required this.player,
    this.width,
    this.height,
    this.radius = 12,
  });
  final ClubRepository repo;
  final Json player;
  final double? width, height;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = '${player['avatarUrl'] ?? ''}';
    final demoAsset = !repo.isProduction
        ? '${player['avatarAsset'] ?? ''}'
        : '';
    final asset = !repo.isProduction
        ? demoAsset.isNotEmpty
              ? demoAsset
              : {
                  'p1': 'assets/demo/player-yu.png',
                  'p2': 'assets/demo/player-bei.png',
                  'p3': 'assets/demo/player-xiaoman.webp',
                  'p4': 'assets/demo/player-north.webp',
                  'p5': 'assets/demo/avatar-nyx.webp',
                  'p6': 'assets/demo/avatar-gale.webp',
                  'p7': 'assets/demo/avatar-abyss.webp',
                  'p8': 'assets/demo/avatar-wing.webp',
                }[player['id']]
        : null;
    final fallback = Container(
      color: sage,
      alignment: Alignment.center,
      child: Text(
        '${player['name'] ?? '?'}'.characters.first,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: forest,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url.startsWith('https://')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : asset != null
            ? Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.3),
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark(this.repo, {super.key, this.size = 40});
  final ClubRepository repo;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: brandColor(repo),
      alignment: Alignment.center,
      child: Text(
        repo.shortName.characters.first,
        style: TextStyle(
          color: onBrand(repo),
          fontSize: size * .42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = '${repo.club['previewLogoUrl'] ?? repo.club['logoUrl'] ?? ''}';
    final asset = '${repo.brand['logoAsset'] ?? ''}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .27),
      child: SizedBox(
        width: size,
        height: size,
        child:
            (url.startsWith('https://') ||
                (!repo.isProduction && url.startsWith('blob:')))
            ? Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              )
            : asset.isNotEmpty
            ? Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.description, {super.key, this.action});
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: rule, width: .6),
          ),
          child: Icon(
            appleChrome(context) ? CupertinoIcons.tray : Icons.inbox_outlined,
            color: faint,
            size: 24,
          ),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: typeSection),
        const SizedBox(height: 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: typeSecondary.copyWith(height: 1.55),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class PairRow extends StatelessWidget {
  const PairRow(this.label, this.value, {super.key, this.strong = false});
  final String label, value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 400 &&
            MediaQuery.textScalerOf(context).scale(15) > 22;
        final labelWidget = Text(label, style: typeSecondary);
        final valueWidget = Text(
          value,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: (strong ? typeBodySmall : typeBodySmall.copyWith(color: ink))
              .copyWith(
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: [_tabular],
              ),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 4), valueWidget],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: labelWidget),
                  const SizedBox(width: 18),
                  Expanded(flex: 3, child: valueWidget),
                ],
              );
      },
    ),
  );
}

/// Floating icon button used over photography. Always has a 44pt hit target.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.size = 34,
    this.dark = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final bool dark;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: dark
          ? const Color(0x6610151B)
          : Colors.white.withValues(alpha: .84),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * .5,
            color: dark ? Colors.white : ink,
          ),
        ),
      ),
    ),
  );
}

/// Frosted count pill over imagery, e.g. "2 / 3".
class ImageBadge extends StatelessWidget {
  const ImageBadge(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x59000000),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x33FFFFFF), width: .5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// Status capsule that maps fulfillment state to one quiet colour pair.
class StagePill extends StatelessWidget {
  const StagePill(this.status, {super.key, this.compact = false});
  final String status;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 8,
      vertical: compact ? 2 : 3,
    ),
    decoration: BoxDecoration(
      color: stageFill(status),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      stageName(status),
      style: TextStyle(
        fontSize: compact ? 10.5 : 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
        color: stageTone(status),
      ),
    ),
  );
}

/// Inset white card that hosts rows separated by hairlines.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: Material(
      color: Colors.white,
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Divider(height: .5, thickness: .5),
                ),
              children[i],
            ],
          ],
        ),
      ),
    ),
  );
}

/// Single menu/info row inside [GroupCard]; the dense iOS grouped-list row.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
  });
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 9 : 12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: typeBodySmall),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: typeSecondary),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (onTap != null)
            const Icon(CupertinoIcons.chevron_forward, size: 14, color: faint),
        ],
      ),
    ),
  );
}

/// Numbered figure used on dashboards. Values keep tabular width.
class MetricBlock extends StatelessWidget {
  const MetricBlock({
    super.key,
    required this.value,
    required this.label,
    this.color = ink,
    this.caption = muted,
    this.align = CrossAxisAlignment.start,
    this.valueStyle,
  });
  final String value, label;
  final Color color, caption;
  final CrossAxisAlignment align;
  final TextStyle? valueStyle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: align,
    children: [
      Text(
        value,
        style:
            valueStyle ??
            typeNumberLarge.copyWith(color: color, fontFeatures: [_tabular]),
      ),
      const SizedBox(height: 4),
      Text(label, style: typeSecondary.copyWith(color: caption)),
    ],
  );
}

/// Deterministic ambient wash used behind hero/guest sections. No blur cost.
class AmbientWash extends StatelessWidget {
  const AmbientWash({
    super.key,
    this.color = const Color(0xFF39508C),
    this.opacity = .28,
  });
  final Color color;
  final double opacity;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _WashPainter(color.withValues(alpha: opacity)),
    child: const SizedBox.expand(),
  );
}

class _WashPainter extends CustomPainter {
  const _WashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final base = Rect.fromLTWH(0, 0, size.width, size.height * .72);
    canvas.drawRect(
      base,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            color.withValues(alpha: color.a * .4),
            const Color(0x00000000),
          ],
        ).createShader(base),
    );
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.75, -.4),
        radius: 1.15,
        colors: [color.withValues(alpha: color.a * .9), const Color(0x00000000)],
      ).createShader(base);
    canvas.drawRect(base, glow);
  }

  @override
  bool shouldRepaint(_WashPainter oldDelegate) => color != oldDelegate.color;
}

Future<T?> showClubSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  Color? backgroundColor,
}) async {
  ModalRoute<dynamic>? sheetRoute;
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      sheetRoute ??= ModalRoute.of(ctx);
      return Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: GlassSurface(
            radius: 26,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: muted.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      );
    },
  );
  // pop 的结果先于退场动画；等路由移除后，调用方才可安全释放输入控制器。
  await sheetRoute?.completed;
  return result;
}

Future<void> textSheet(BuildContext context, String title, String text) =>
    showClubSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .75,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: typeTitle),
                  const SizedBox(height: 12),
                  SelectableText(
                    text,
                    style: typeBodySmall.copyWith(height: 1.7),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

/// Sheet heading shared by every modal form (22pt title + 12pt caption).
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key, this.caption, this.trailing});
  final String title;
  final String? caption;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: typeTitle),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(caption!, style: typeSecondary),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Small footer that keeps the fictional-data disclosure on preview surfaces.
class DemoStamp extends StatelessWidget {
  const DemoStamp(this.repo, {super.key, this.text});
  final ClubRepository repo;
  final String? text;
  @override
  Widget build(BuildContext context) {
    if (repo.isProduction) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.info_circle, size: 12, color: faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text ??
                  '${repo.club['notice'] ?? '虚构演示俱乐部'} · 人物、服务与订单均为示例，不提供真实服务或收款。',
              style: typeCaption.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
