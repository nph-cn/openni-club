import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'accessibility.dart';

const canvas = Color(0xFFF5F6F8),
    ink = Color(0xFF171B21),
    muted = Color(0xFF5E6673),
    rule = Color(0xFFDDE1E7),
    sage = Color(0xFFE9EDF2),
    sand = Color(0xFFEEF0F4),
    forest = Color(0xFF272D35);
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

ThemeData clubTheme(ClubRepository repo) => ThemeData(
  useMaterial3: true,
  platform: kIsWeb ? TargetPlatform.iOS : defaultTargetPlatform,
  fontFamily: 'NotoSansSC',
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: brandColor(repo),
    primary: brandColor(repo),
    onPrimary: onBrand(repo),
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleSmall: TextStyle(
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodySmall: TextStyle(fontSize: 14, height: 1.45, color: muted),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 16, height: 1.5, color: ink),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
  ),
  iconTheme: const IconThemeData(color: ink, size: 22),
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: brandColor(repo),
    checkmarkColor: onBrand(repo),
    secondaryLabelStyle: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 16,
      color: onBrand(repo),
    ),
    labelStyle: const TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 16,
      color: ink,
    ),
    side: const BorderSide(color: rule),
  ),
  dividerTheme: const DividerThemeData(color: rule, space: 28, thickness: 1),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: rule),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: rule),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: rule),
    ),
    contentPadding: const EdgeInsets.all(16),
  ),
);

bool appleChrome(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
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
          color: Colors.white.withValues(alpha: opaque ? 1 : .74),
          borderRadius: BorderRadius.circular(radius),
          border: border
              ? Border.all(color: Colors.white.withValues(alpha: .9), width: .5)
              : null,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: opaque
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: surface,
              ),
      );
    },
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
    final showBar = tab != null || bottom != null;
    final nav = tab == null
        ? null
        : NavigationBar(
            selectedIndex: tab!,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            height: 62,
            animationDuration: media.disableAnimations || media.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            indicatorColor: brandColor(repo).withValues(alpha: .07),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 13,
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
    return Scaffold(
      extendBody: apple && showBar,
      extendBodyBehindAppBar: apple && appBar,
      appBar: !appBar
          ? null
          : AppBar(
              backgroundColor: apple ? Colors.transparent : canvas,
              scrolledUnderElevation: 0,
              title: Text(title ?? ''),
              flexibleSpace: apple
                  ? const GlassSurface(
                      radius: 0,
                      border: false,
                      child: SizedBox.expand(),
                    )
                  : null,
              leading: tab != null
                  ? null
                  : IconButton(
                      tooltip: '返回',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
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
                    ),
              actions: actions,
            ),
      body: _PageInsets(
        top: apple && appBar ? kToolbarHeight + media.padding.top : 0,
        bottom: apple && showBar ? 84 + media.padding.bottom : 0,
        child: SafeArea(
          top: !appBar,
          bottom: !apple,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: child,
            ),
          ),
        ),
      ),
      bottomNavigationBar: !showBar
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: apple
                    ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
                    : EdgeInsets.zero,
                child: Container(
                  decoration: apple
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            bottom != null ? 20 : 24,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ink.withValues(alpha: .075),
                              blurRadius: 24,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        )
                      : null,
                  child: GlassSurface(
                    radius: apple ? (bottom != null ? 20 : 24) : 0,
                    child: bottom != null
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: bottom!,
                          )
                        : nav!,
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
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
      padding:
          padding +
          EdgeInsets.only(top: inset?.top ?? 0, bottom: inset?.bottom ?? 0),
      children: children,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.caption,
    this.action,
    this.onTap,
  });
  final String title;
  final String? caption, action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.2,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Row(
              children: [
                Text(action!, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      border: fill == Colors.transparent ? Border.all(color: rule) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(18),
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
      borderRadius: BorderRadius.circular(16),
      border: border ? Border.all(color: rule) : null,
    ),
    child: child,
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
    final asset = !repo.isProduction
        ? {
            'p1': 'assets/demo/player-yu.png',
            'p2': 'assets/demo/player-bei.png',
          }[player['id']]
        : null;
    final fallback = Container(
      color: sage,
      alignment: Alignment.center,
      child: Text(
        '${player['name'] ?? '?'}'.characters.first,
        style: const TextStyle(
          fontSize: 32,
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final url = '${repo.club['previewLogoUrl'] ?? repo.club['logoUrl'] ?? ''}';
    final asset = '${repo.brand['logoAsset'] ?? ''}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: SizedBox(
        width: size,
        height: size,
        child:
            (url.startsWith('https://') ||
                (!repo.isProduction && url.startsWith('blob:')))
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : asset.isNotEmpty
            ? Image.asset(
                asset,
                fit: BoxFit.cover,
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
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, color: muted, size: 40),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
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
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 16)),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 16,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<T?> showClubSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  Color? backgroundColor,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  backgroundColor: Colors.transparent,
  builder: (ctx) => GlassSurface(
    radius: 28,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDragHandle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36,
              height: 5,
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
);

Future<void> textSheet(BuildContext context, String title, String text) =>
    showClubSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .75,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    text,
                    style: const TextStyle(fontSize: 16, height: 1.7),
                  ),
                  const SizedBox(height: 24),
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
