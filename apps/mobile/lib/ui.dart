import 'dart:ui' show ImageFilter;

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

const canvas = Color(0xFFF2F3F6),
    ink = Color(0xFF171B21),
    muted = Color(0xFF5E6673),
    rule = Color(0xFFE2E5EB),
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

ThemeData clubTheme(ClubRepository repo, {bool previewFonts = false}) {
  final fontFamily = kIsWeb || previewFonts ? 'NotoSansSC' : null;
  return ThemeData(
    useMaterial3: true,
    platform: kIsWeb ? TargetPlatform.iOS : defaultTargetPlatform,
    fontFamily: fontFamily,
    splashFactory: NoSplash.splashFactory,
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
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
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
        fontFamily: fontFamily,
        fontSize: 16,
        color: onBrand(repo),
      ),
      labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 16, color: ink),
      side: const BorderSide(color: Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: rule, space: 28, thickness: .7),
    listTileTheme: ListTileThemeData(
      minTileHeight: 64,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: muted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        color: Colors.white,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        backgroundColor: Colors.white.withValues(alpha: .65),
        side: const BorderSide(color: rule),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: rule),
      ),
      contentPadding: const EdgeInsets.all(16),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: brandColor(repo), width: 1.5),
      ),
    ),
  );
}

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
          color: opaque ? Colors.white : null,
          gradient: opaque
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xC9FFFFFF),
                    Color(0x99F3F6FC),
                    Color(0xB8FFFFFF),
                  ],
                  stops: [0, .55, 1],
                ),
          borderRadius: BorderRadius.circular(radius),
          border: border
              ? Border.all(
                  color: opaque ? rule : Colors.white.withValues(alpha: .5),
                  width: 1,
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
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
      padding: const EdgeInsets.all(5),
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
                    borderRadius: BorderRadius.circular(27),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(27),
                        color: selected == i
                            ? Colors.white.withValues(alpha: .94)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected == i
                              ? Colors.white
                              : Colors.transparent,
                        ),
                        boxShadow: selected == i
                            ? [
                                BoxShadow(
                                  color: ink.withValues(alpha: .08),
                                  blurRadius: 12,
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
                              size: 23,
                              color: selected == i ? ink : muted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
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
      if (!appleChrome(context)) {
        return TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: submit,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: hintText,
            suffixIcon: hasText
                ? IconButton(
                    tooltip: '清除搜索',
                    onPressed: clear,
                    icon: const Icon(Icons.cancel_rounded, size: 20),
                  )
                : null,
          ),
        );
      }
      return Stack(
        alignment: Alignment.centerRight,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: CupertinoSearchTextField(
              controller: controller,
              placeholder: hintText,
              onChanged: onChanged,
              onSubmitted: submit,
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: 16,
                color: ink,
              ),
              placeholderStyle: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: 16,
                color: muted,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rule, width: .7),
              ),
              itemColor: muted,
              itemSize: 20,
              prefixInsets: const EdgeInsetsDirectional.fromSTEB(14, 0, 8, 0),
              padding: EdgeInsetsDirectional.fromSTEB(
                0,
                13,
                hasText ? 48 : 14,
                13,
              ),
              suffixMode: OverlayVisibilityMode.never,
            ),
          ),
          if (hasText)
            PositionedDirectional(
              end: 2,
              child: IconButton(
                tooltip: '清除搜索',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: clear,
                icon: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 20,
                  color: muted,
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
          backgroundColor: const Color(0xFFE6E9EE),
          thumbColor: Colors.white,
          padding: const EdgeInsets.all(4),
          children: {
            for (final option in values)
              option: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    fontFamily: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.fontFamily,
                    fontSize: 16,
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
        (media.textScaler.scale(tab != null ? 26 : 17) * 1.3 + 16).clamp(
          kToolbarHeight,
          double.infinity,
        );
    final chromeInset =
        (media.size.width - media.padding.horizontal - 620).clamp(
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
            height: 62,
            animationDuration: media.disableAnimations || media.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            indicatorColor: brandColor(repo).withValues(alpha: .07),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
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
    final backButton = IconButton(
      tooltip: '返回',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .78),
        padding: const EdgeInsets.all(12),
      ),
      icon: Icon(
        apple ? CupertinoIcons.chevron_back : Icons.arrow_back_rounded,
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
              leadingWidth: tab == null ? 56 + chromeInset : null,
              titleSpacing: tab != null ? 22 : null,
              title: Padding(
                padding: EdgeInsets.only(left: tab != null ? chromeInset : 0),
                child: Text(
                  title ?? '',
                  style: TextStyle(
                    fontSize: tab != null ? 26 : 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
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
              ? MediaQuery.paddingOf(bodyContext).bottom + 16
              : 0,
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
      ),
      bottomNavigationBar: !showBar
          ? null
          : SafeArea(
              top: false,
              child: Center(
                heightFactor: 1,
                child: SizedBox(
                  width: 620,
                  child: Padding(
                    padding: apple
                        ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
                        : EdgeInsets.zero,
                    child: Container(
                      decoration: apple
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                bottom != null ? 26 : 34,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ink.withValues(alpha: .12),
                                  blurRadius: 30,
                                  offset: const Offset(0, 9),
                                ),
                              ],
                            )
                          : null,
                      child: GlassSurface(
                        radius: apple ? (bottom != null ? 26 : 34) : 0,
                        child: bottom != null
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
    padding: const EdgeInsets.only(top: 16, bottom: 12),
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
                  fontSize: 22,
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
                const Icon(Icons.chevron_right_rounded, size: 19),
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
      borderRadius: BorderRadius.circular(9),
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
      borderRadius: BorderRadius.circular(23),
      border: Border.all(
        color: border ? rule : Colors.white.withValues(alpha: .8),
        width: .7,
      ),
      boxShadow: color == Colors.white
          ? [
              BoxShadow(
                color: ink.withValues(alpha: .025),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ]
          : null,
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
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
    child: Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: rule, width: .6),
          ),
          child: Icon(
            appleChrome(context) ? CupertinoIcons.tray : Icons.inbox_outlined,
            color: muted,
            size: 32,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 15, height: 1.55),
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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 400 &&
            MediaQuery.textScalerOf(context).scale(16) > 24;
        final labelWidget = Text(
          label,
          style: const TextStyle(color: muted, fontSize: 16),
        );
        final valueWidget = Text(
          value,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            fontSize: 16,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
          ),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 6), valueWidget],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: labelWidget),
                  const SizedBox(width: 24),
                  Expanded(flex: 3, child: valueWidget),
                ],
              );
      },
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
