import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'repository.dart';
import 'ui.dart';
import 'discover.dart';
import 'orders.dart';
import 'booking.dart';
import 'member.dart';
import 'club_programs.dart';
import 'accessibility.dart';
import 'auth.dart';
import 'loading.dart';
import 'device_preview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ClubBootstrap(
      repository: ClubRepository(),
      initialScreen: Uri.base.queryParameters['screen'] ?? 'home',
    ),
  );
}

class ClubBootstrap extends StatefulWidget {
  const ClubBootstrap({
    super.key,
    required this.repository,
    this.initialScreen = 'home',
    this.loader,
  });
  final ClubRepository repository;
  final String initialScreen;
  final Future<void> Function()? loader;
  @override
  State<ClubBootstrap> createState() => _ClubBootstrapState();
}

class _ClubBootstrapState extends State<ClubBootstrap> {
  late Future<void> future = start();
  Future<void> start() async {
    if (widget.loader != null) {
      await widget.loader!();
      return;
    }
    await GlassPreferences.initialize();
    final repo = widget.repository;
    await repo.load();
    if (repo.error != null) throw Exception(repo.error);
    await repo.loadDemoPreview();
    if (repo.isLocal &&
        !repo.isProduction &&
        [
          'member',
          'member_orders',
          'member_order',
          'member_order_running',
          'member_order_completed',
          'availability',
          'earnings',
          'member_notifications',
          'delivery',
        ].contains(widget.initialScreen)) {
      await repo.loadMemberData();
    }
    if (kIsWeb && !repo.isProduction) applyBrandPreview(repo, Uri.base);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return OpenNIApp(
          repository: widget.repository,
          initialScreen: widget.initialScreen,
          previewDevice:
              kIsWeb && Uri.base.queryParameters['device'] == 'iphone',
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: clubTheme(widget.repository),
        home: ClubPage(
          repo: widget.repository,
          appBar: false,
          child: snapshot.hasError
              ? ConnectionFailure(
                  onRetry: () => setState(() => future = start()),
                )
              : const ClubSkeleton(kind: SkeletonKind.home),
        ),
      );
    },
  );
}

class ConnectionFailure extends StatelessWidget {
  const ConnectionFailure({super.key, required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => PageList(
    padding: const EdgeInsets.fromLTRB(20, 96, 20, 24),
    children: [
      Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: rule, width: .6),
        ),
        child: const Icon(Icons.cloud_off_rounded, size: 26, color: faint),
      ),
      const SizedBox(height: 20),
      const Text('暂时无法连接', style: typeTitle),
      const SizedBox(height: 6),
      const Text('请检查网络连接后重试。', style: typeSecondary),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 17),
        label: const Text('重新加载'),
      ),
      const SizedBox(height: 14),
      Text(
        '当前为 OpenNI 演示客户端，连接俱乐部需要配置可用的 HTTPS API。',
        style: typeCaption.copyWith(height: 1.5),
      ),
    ],
  );
}

/// Browser Studio overrides only presentation. Never touches API, auth or mode.
void applyBrandPreview(ClubRepository repo, Uri uri) {
  if (repo.isProduction) return;
  final query = uri.queryParameters;
  final name = query['previewName']?.trim();
  if (name != null && name.isNotEmpty && name.length <= 60) {
    repo.club.addAll({'name': name, 'shortName': name});
  }
  final color = query['previewColor'];
  if (color != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
    repo.club['primaryColor'] = color;
  }
  final logo = query['previewLogo'];
  if (logo != null && logo.startsWith('blob:')) {
    final origin = Uri.tryParse(logo.substring(5));
    if (origin != null &&
        origin.hasAuthority &&
        ['http', 'https'].contains(origin.scheme) &&
        origin.origin == uri.origin) {
      repo.club['previewLogoUrl'] = logo;
    }
  }
}

class OpenNIApp extends StatefulWidget {
  const OpenNIApp({
    super.key,
    required this.repository,
    this.initialScreen = 'home',
    this.previewDevice = false,
  });
  final ClubRepository repository;
  final String initialScreen;
  final bool previewDevice;
  @override
  State<OpenNIApp> createState() => _OpenNIAppState();
}

class _OpenNIAppState extends State<OpenNIApp> {
  ClubRepository get repo => widget.repository;
  late final GoRouter router;
  Widget live(Widget Function() builder) => ListenableBuilder(
    listenable: repo,
    builder: (_, _) => repo.loading
        ? ClubPage(
            repo: repo,
            appBar: false,
            child: const ClubSkeleton(kind: SkeletonKind.home),
          )
        : repo.error != null
        ? ClubPage(
            repo: repo,
            title: '连接俱乐部',
            child: EmptyState(
              '暂时无法连接',
              repo.error!,
              action: FilledButton(
                onPressed: repo.load,
                child: const Text('重试'),
              ),
            ),
          )
        : builder(),
  );
  @override
  void initState() {
    super.initState();
    final serviceId = repo.services.firstOrNull?['id'] ?? 's1',
        playerId = repo.players.firstOrNull?['id'] ?? 'p1',
        orderId = repo.orders.firstOrNull?['id'] ?? 'none';
    final inProgressOrderId = repo.memberOrders
            .where((o) => stage(o) == 'in_progress')
            .firstOrNull?['id'] ??
        'none';
    final completedOrderId = repo.memberOrders
            .where((o) => stage(o) == 'completed')
            .firstOrNull?['id'] ??
        'none';
    final initial =
        {
          'home': '/',
          'welcome': '/welcome',
          'login': '/login',
          'phone': '/login/phone',
          'code': '/login/code',
          'code_error': '/login/code?state=error',
          'code_verifying': '/login/code?state=verifying',
          'home_loading': '/states/loading',
          'home_error': '/states/error',
          'home_empty': '/states/home-empty',
          'orders_empty': '/states/orders-empty',
          'orders_guest': '/states/orders-guest',
          'orders_loading': '/states/loading-orders',
          'profile_loading': '/states/loading-profile',
          'member_loading': '/states/loading-member',
          'notifications_loading': '/states/loading-notifications',
          'tiers_loading': '/states/loading-tiers',
          'club_features_loading': '/states/loading-features',
          'privacy': '/legal/privacy',
          'terms': '/legal/terms',
          'home_android': '/',
          'services': '/services',
          'services_valorant': '/services?game=${Uri.encodeComponent('无畏契约')}',
          'service': '/services/$serviceId',
          'service_120':
              '/services/$serviceId?variant=${serviceVariants(repo.services.firstOrNull ?? {}).lastOrNull?['id'] ?? ''}',
          'service_review': '/services/s2',
          'service_valorant': '/services/s3',
          'service_lol': '/services/s4',
          'service_with_player': '/services/$serviceId?player=$playerId',
          'players': '/players',
          'players_valorant': '/players?game=${Uri.encodeComponent('无畏契约')}',
          'following': '/players?following=1',
          'player': '/players/$playerId',
          'player_echo': '/players/p2',
          'player_xiaoman': '/players/p3',
          'player_north': '/players/p4',
          'booking': '/book?service=$serviceId',
          'checkout': '/book?service=$serviceId&preview=checkout',
          'orders': '/orders',
          'order': '/orders/$orderId',
          'support': '/orders/$orderId/support',
          'profile': '/profile',
          'settings': '/settings',
          'announcements': '/announcements',
          'notifications': '/notifications',
          'member_notifications': '/notifications',
          'member': '/member',
          'member_orders': '/member/orders',
          'member_order':
              '/member/orders/${repo.memberOrders.where((o) => stage(o) == 'awaiting_acceptance').firstOrNull?['id'] ?? repo.memberOrders.firstOrNull?['id'] ?? 'none'}',
          'member_order_running': '/member/orders/$inProgressOrderId',
          'member_order_completed': '/member/orders/$completedOrderId',
          'delivery':
              '/member/orders/$inProgressOrderId?delivery=1',
          'availability': '/member/availability',
          'earnings': '/member/earnings',
          'tiers': '/club/tiers',
          'club_features': '/club/features',
        }[widget.initialScreen] ??
        '/';
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (_, s) => AuthPage(
            repo,
            kind: 'welcome',
            next: safeReturnPath(s.uri.queryParameters['next']),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, s) => AuthPage(
            repo,
            next: safeReturnPath(s.uri.queryParameters['next']),
          ),
        ),
        GoRoute(
          path: '/login/phone',
          builder: (_, s) => AuthPage(
            repo,
            kind: 'phone',
            next: safeReturnPath(s.uri.queryParameters['next']),
          ),
        ),
        GoRoute(
          path: '/login/code',
          builder: (_, s) => AuthPage(
            repo,
            kind: 'code',
            previewError:
                !repo.isProduction &&
                repo.isLocal &&
                s.uri.queryParameters['state'] == 'error',
            previewSubmitting:
                !repo.isProduction &&
                repo.isLocal &&
                s.uri.queryParameters['state'] == 'verifying',
            verifyCode:
                !repo.isProduction &&
                    repo.isLocal &&
                    s.uri.queryParameters['state'] == 'verifying'
                ? (_, _) => Completer<void>().future
                : null,
            next: safeReturnPath(s.uri.queryParameters['next']),
          ),
        ),
        if (!repo.isProduction && repo.isLocal) ...[
          GoRoute(
            path: '/states/orders-guest',
            builder: (context, _) => OrdersSignInPage(
              repo,
              onSignIn: () => context.push('/login?next=%2Forders'),
            ),
          ),
          GoRoute(
            path: '/states/orders-empty',
            builder: (_, _) {
              final empty = ClubRepository(persist: false)
                ..brand = repo.brand
                ..club = repo.club
                ..services = repo.services
                ..players = repo.players;
              return OrdersPage(empty);
            },
          ),
          GoRoute(
            path: '/states/home-empty',
            builder: (_, _) {
              final empty = ClubRepository(persist: false)
                ..brand = repo.brand
                ..club = repo.club;
              return HomePage(empty);
            },
          ),
          GoRoute(
            path: '/states/loading',
            builder: (_, _) => ClubPage(
              repo: repo,
              appBar: false,
              child: const ClubSkeleton(kind: SkeletonKind.home),
            ),
          ),
          GoRoute(
            path: '/states/loading-orders',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '我的订单',
              tab: 2,
              child: const ClubSkeleton(kind: SkeletonKind.catalog),
            ),
          ),
          GoRoute(
            path: '/states/loading-profile',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '我的',
              tab: 3,
              child: const ClubSkeleton(kind: SkeletonKind.profile),
            ),
          ),
          GoRoute(
            path: '/states/loading-member',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '成员工作台',
              tab: 0,
              child: const ClubSkeleton(kind: SkeletonKind.member),
            ),
          ),
          GoRoute(
            path: '/states/loading-notifications',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '通知',
              child: const ClubSkeleton(kind: SkeletonKind.notifications),
            ),
          ),
          GoRoute(
            path: '/states/loading-tiers',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '打手分级',
              child: const ClubSkeleton(kind: SkeletonKind.tiers),
            ),
          ),
          GoRoute(
            path: '/states/loading-features',
            builder: (_, _) => ClubPage(
              repo: repo,
              title: '俱乐部能力',
              child: const ClubSkeleton(kind: SkeletonKind.clubFeatures),
            ),
          ),
          GoRoute(
            path: '/states/error',
            builder: (_, _) => ClubPage(
              repo: repo,
              appBar: false,
              child: ConnectionFailure(
                onRetry: () async {
                  await repo.load();
                  if (mounted && repo.error == null) router.go('/');
                },
              ),
            ),
          ),
        ],
        GoRoute(path: '/', builder: (_, _) => live(() => HomePage(repo))),
        GoRoute(
          path: '/services',
          builder: (_, s) => live(
            () => ServicesPage(
              repo,
              initialGame: s.uri.queryParameters['game'] ?? '全部',
            ),
          ),
        ),
        GoRoute(
          path: '/services/:id',
          builder: (_, s) => live(
            () => ServicePage(
              repo,
              s.pathParameters['id']!,
              initialVariant: s.uri.queryParameters['variant'],
              playerId: s.uri.queryParameters['player'],
            ),
          ),
        ),
        GoRoute(
          path: '/players',
          builder: (_, s) => live(
            () => PlayersPage(
              repo,
              initialGame: s.uri.queryParameters['game'] ?? '全部',
              onlyFollowing: s.uri.queryParameters['following'] == '1',
            ),
          ),
        ),
        GoRoute(
          path: '/players/:id',
          builder: (_, s) => live(
            () => PlayerPage(
              repo,
              s.pathParameters['id']!,
              serviceId: s.uri.queryParameters['service'],
              variantId: s.uri.queryParameters['variant'],
            ),
          ),
        ),
        GoRoute(
          path: '/book',
          builder: (_, s) => live(
            () => BookingPage(
              repo,
              s.uri.queryParameters['service'] ?? '',
              playerId: s.uri.queryParameters['player'],
              variantId: s.uri.queryParameters['variant'],
              previewCheckout: s.uri.queryParameters['preview'] == 'checkout',
            ),
          ),
        ),
        GoRoute(
          path: '/orders',
          builder: (_, _) => live(() => OrdersPage(repo)),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, s) =>
              live(() => OrderPage(repo, s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/orders/:id/support',
          builder: (_, s) =>
              live(() => SupportPage(repo, s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/legal/:kind',
          builder: (_, s) => PolicyPage(repo, kind: s.pathParameters['kind']!),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => live(() => AccountPage(repo)),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => live(() => AccountPage(repo, settings: true)),
        ),
        GoRoute(
          path: '/announcements',
          builder: (_, _) => live(() => AnnouncementsPage(repo)),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => live(() => NotificationsPage(repo)),
        ),
        for (final path in ['/member', '/member/orders', '/member/earnings'])
          GoRoute(
            path: path,
            builder: (_, _) => live(
              () => MemberPage(
                repo,
                mode: path == '/member'
                    ? 'home'
                    : path.endsWith('earnings')
                    ? 'earnings'
                    : 'orders',
              ),
            ),
          ),
        GoRoute(
          path: '/member/orders/:id',
          builder: (_, s) => live(
            () => MemberPage(
              repo,
              mode: 'order',
              orderId: s.pathParameters['id'],
              openDelivery: s.uri.queryParameters['delivery'] == '1',
            ),
          ),
        ),
        GoRoute(
          path: '/member/availability',
          builder: (_, _) => live(() => AvailabilityPage(repo)),
        ),
        GoRoute(
          path: '/club/tiers',
          builder: (_, _) => live(() => TiersPage(repo)),
        ),
        GoRoute(
          path: '/club/features',
          builder: (_, _) => live(() => ClubFeaturesPage(repo)),
        ),
      ],
      errorBuilder: (_, _) => ClubPage(
        repo: repo,
        title: '页面未找到',
        child: const EmptyState('这个入口暂不可用', '请返回俱乐部首页。'),
      ),
    );
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (_, _) => MaterialApp.router(
      title: repo.clubName,
      debugShowCheckedModeBanner: false,
      theme: widget.initialScreen == 'home_android' && !repo.isProduction
          ? clubTheme(
              repo,
              previewFonts: widget.previewDevice,
            ).copyWith(platform: TargetPlatform.android)
          : clubTheme(repo, previewFonts: widget.previewDevice),
      builder: (context, child) =>
          widget.previewDevice &&
              !repo.isProduction &&
              widget.initialScreen != 'home_android'
          ? IPhonePreview(child: child!)
          : child!,
      routerConfig: router,
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage(this.repo, {super.key, this.settings = false});
  final ClubRepository repo;
  final bool settings;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  ClubRepository get repo => widget.repo;
  bool get settings => widget.settings;
  bool busy = false, accountLoading = false;
  String? accountFailure;
  @override
  void initState() {
    super.initState();
    if (!repo.isLocal && repo.token != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) readAccount();
      });
    }
  }

  Future<void> readAccount() async {
    setState(() {
      accountLoading = true;
      accountFailure = null;
    });
    try {
      await repo.loadAccount();
    } catch (e) {
      if (mounted) setState(() => accountFailure = '$e');
    } finally {
      if (mounted) setState(() => accountLoading = false);
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() async {
    final ok = await context.push<bool>('/login?next=%2Fprofile');
    if (ok == true && mounted) {
      await run(() async {
        await repo.loadAccount();
        await repo.refreshOrders();
      });
    }
  }

  Future<void> edit(
    String title,
    String initial,
    Future<void> Function(String) save,
  ) async {
    final controller = TextEditingController(text: initial);
    final value = await showClubSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(title, caption: '保存后会同步到俱乐部账号。'),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: title == '修改昵称' ? 30 : 100,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(counterText: '', hintText: '请输入'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty && mounted) {
      await run(() => save(value));
    }
  }

  Widget _profileHeader() {
    final member = repo.role == 'member' ? repo.findPlayer(repo.memberPlayerId) : null;
    final latest = repo.orders.firstOrNull;
    final service = latest == null
        ? repo.services.firstOrNull
        : repo.findService('${latest['serviceId']}');
    final name = repo.token == null && repo.role != 'member'
        ? '欢迎来到俱乐部'
        : repo.memberName;
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: SizedBox(
        height: 166,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (service != null) ServiceArt(service, radius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xE60E131A), Color(0xB3253040), Color(0x730E131A)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (member != null)
                        PlayerArt(
                          repo: repo,
                          player: member,
                          width: 44,
                          height: 48,
                          radius: 13,
                        )
                      else if (repo.token != null)
                        Container(
                          width: 44,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .3),
                              width: .6,
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.person_fill,
                            size: 20,
                            color: Colors.white,
                          ),
                        )
                      else
                        BrandMark(repo, size: 44),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              repo.role == 'member'
                                  ? '俱乐部成员'
                                  : repo.token == null
                                  ? '登录后管理你的预约'
                                  : '俱乐部客户 · 示例账号',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xCCFFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (settings)
                        const Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: Color(0xCCFFFFFF),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (repo.token == null && !settings)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : login,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              backgroundColor: Colors.white,
                              foregroundColor: ink,
                            ),
                            child: const Text('登录 / 注册'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .26),
                                width: .6,
                              ),
                            ),
                            child: Text(
                              '浏览服务无需登录',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: .92),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '演示账号 · 数据仅本机',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xD9FFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _metrics() => [
    Row(
      children: [
        Expanded(
          child: _AccountMetric(
            title: '我的预约',
            count: repo.orders.length,
            icon: CupertinoIcons.calendar,
            onTap: () => context.go('/orders'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AccountMetric(
            title: '本机关注',
            count: repo.following.length,
            icon: CupertinoIcons.heart,
            onTap: () => context.push('/players?following=1'),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _menu() {
    final rows = <Widget>[
      if (settings && (repo.isLocal || repo.token != null))
        GroupRow(
          leading: const Icon(CupertinoIcons.pencil, size: 17),
          title: '修改昵称',
          subtitle: repo.memberName,
          onTap: busy
              ? null
              : () => edit('修改昵称', repo.memberName, repo.rename),
        ),
      if (settings && !repo.isLocal && repo.role != 'member')
        GroupRow(
          leading: const Icon(CupertinoIcons.person_badge_plus, size: 17),
          title: '接受成员邀请',
          subtitle: '输入俱乐部发放的邀请码',
          onTap: busy
              ? null
              : () => edit('输入俱乐部邀请码', '', repo.acceptInvitation),
        ),
      if (!settings)
        GroupRow(
          leading: const Icon(Icons.military_tech_outlined, size: 17),
          title: '打手分级',
          subtitle: '分级、认证与分成规则',
          onTap: () => context.push('/club/tiers'),
        ),
      if (!settings)
        GroupRow(
          leading: const Icon(Icons.tune_rounded, size: 17),
          title: '俱乐部能力',
          subtitle:
              '已开通 ${repo.clubFeatures.where((f) => f['enabled'] == true).length}/${repo.clubFeatures.length} 项',
          onTap: () => context.push('/club/features'),
        ),
      GroupRow(
        leading: const Icon(CupertinoIcons.lock_shield, size: 17),
        title: '隐私政策',
        onTap: () => context.push('/legal/privacy'),
      ),
      GroupRow(
        leading: const Icon(CupertinoIcons.doc_text, size: 17),
        title: '服务与退款说明',
        onTap: () => context.push('/legal/terms'),
      ),
      GroupRow(
        leading: const Icon(
          CupertinoIcons.bubble_left_bubble_right,
          size: 17,
        ),
        title: '联系俱乐部',
        onTap: () => textSheet(
          context,
          '联系俱乐部',
          '${repo.club['supportContact'] ?? '请通过运营方公示渠道联系。'}',
        ),
      ),
      if (!settings)
        GroupRow(
          leading: const Icon(CupertinoIcons.gear, size: 17),
          title: '设置与关于',
          subtitle: '昵称、演示模式与账号',
          onTap: () => context.push('/settings'),
        ),
    ];
    return [
      if (!settings)
        GroupRow(
          leading: const Icon(CupertinoIcons.bell, size: 17),
          title: '通知与进度',
          subtitle: '预约安排与服务进度更新',
          onTap: () => context.push('/notifications'),
        ),
      if (!settings)
        GroupRow(
          leading: const Icon(Icons.campaign_outlined, size: 17),
          title: '俱乐部动态',
          subtitle: '公告与运营说明',
          onTap: () => context.push('/announcements'),
        ),
      ...rows,
    ];
  }

  @override
  Widget build(BuildContext context) => ClubPage(
    repo: repo,
    title: settings ? '设置' : '我的',
    tab: settings ? null : 3,
    child: accountLoading && !settings
        ? const ClubSkeleton(kind: SkeletonKind.profile)
        : PageList(
            children: [
              if (accountFailure != null)
                EmptyState(
                  '资料加载失败',
                  accountFailure!,
                  action: TextButton(
                    onPressed: readAccount,
                    child: const Text('重新加载'),
                  ),
                ),
              if (!settings) ...[
                const SizedBox(height: 2),
                _profileHeader(),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 10),
                ..._metrics(),
              ],
              const SizedBox(height: 14),
              GroupCard(children: _menu()),
              if (settings && !repo.isProduction) ...[
                const SectionTitle('关于当前预览'),
                Surface(
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          BrandMark(repo, size: 26),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${repo.clubName} · OpenNI 演示客户端',
                              style: typeBodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        '俱乐部、成员、订单与金额为示例资料，不提供真实服务或收款。人物为原创虚构形象；游戏图片来自发行商，版权归原权利人。',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await repo.switchDemoRole(
                            repo.role == 'member' ? 'customer' : 'member',
                            playerId: repo.players.firstOrNull?['id'],
                          );
                          if (context.mounted) {
                            context.go(repo.role == 'member' ? '/member' : '/');
                          }
                        }),
                  child: Text(repo.role == 'member' ? '切换到客户体验' : '切换到成员体验'),
                ),
              ],
              if (settings) ...[
                const SizedBox(height: 10),
                GroupCard(
                  children: [
                    if (repo.token != null)
                      GroupRow(
                        leading: const Icon(
                          CupertinoIcons.square_arrow_right,
                          size: 17,
                        ),
                        title: '退出登录',
                        onTap: busy
                            ? null
                            : () => run(() async {
                                await repo.signOut();
                                if (context.mounted) context.go('/profile');
                              }),
                      ),
                    GroupRow(
                      leading: const Icon(
                        CupertinoIcons.person_crop_circle_badge_minus,
                        size: 17,
                      ),
                      title: repo.isLocal ? '清除本地数据' : '注销账号',
                      onTap: !repo.isLocal && repo.token == null
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('确认清除账号资料？'),
                                  content: const Text('此操作无法恢复。未完成订单与退款需要先处理。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('保留资料'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('确认清除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                try {
                                  await repo.deleteAccount();
                                  if (context.mounted) {
                                    toast(context, '资料已清除。');
                                  }
                                } catch (e) {
                                  if (context.mounted) toast(context, e);
                                }
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: repo.clubName,
                    ),
                    child: const Text('OpenNI · 开源许可'),
                  ),
                ),
              ],
              DemoStamp(repo),
            ],
          ),
  );
}

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: sage,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: ink),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: typeLabel.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 1),
                  Text(title, style: typeCaption),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 12,
              color: faint,
            ),
          ],
        ),
      ),
    ),
  );
}

class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  Widget build(BuildContext context) {
    final service = repo.services.firstOrNull;
    return ClubPage(
      repo: repo,
      title: '俱乐部动态',
      child: repo.announcements.isEmpty
          ? const EmptyState('暂无公告', '俱乐部发布的通知会显示在这里')
          : PageList(
              children: [
                if (service != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: SizedBox(
                      height: 118,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ServiceArt(service, radius: 0),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Color(0xE60E131A),
                                  Color(0x800E131A),
                                  Color(0x1A0E131A),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${repo.clubName} · 动态',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  '公告与运营说明均由俱乐部发布',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xCCFFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                for (final a in repo.announcements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Surface(
                      border: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Tag('公告', fill: sage, color: muted),
                              const Spacer(),
                              Text(when(a['publishedAt']), style: typeCaption),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${a['title']}',
                            style: typeSection,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${a['body']}',
                            style: typeSecondary.copyWith(height: 1.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                DemoStamp(repo),
              ],
            ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? error;
  bool loading = false;
  String filter = '全部';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (widget.repo.isLocal) return;
    if (widget.repo.isProduction && widget.repo.token == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.repo.signIn();
      final data = await widget.repo.request('GET', '/notifications');
      widget.repo.notifications = (data as List)
          .map((e) => Json.from(e))
          .toList();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Widget> notificationGroups() {
    final groups = <String, List<Json>>{};
    final items =
        widget.repo.notifications.where((n) {
          final unread = n['readAt'] == null;
          return filter == '全部' || unread;
        }).toList()..sort(
          (a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'),
        );
    for (final item in items) {
      final time = DateTime.tryParse('${item['createdAt']}')
          ?.toUtc()
          .add(const Duration(hours: 8));
      final label = time == null ? '消息' : '${time.month}月${time.day}日';
      (groups[label] ??= []).add(item);
    }
    return [
      for (final group in groups.entries) ...[
        SectionTitle(group.key),
        GroupCard(
          children: [
            for (final n in group.value) notificationRow(n),
          ],
        ),
      ],
    ];
  }

  Widget notificationRow(Json n) {
    final unread = n['readAt'] == null;
    final member = widget.repo.role == 'member';
    final player = member
        ? widget.repo.findPlayer(widget.repo.memberPlayerId)
        : null;
    return InkWell(
      onTap: () async {
        try {
          if (!widget.repo.isLocal) {
            await widget.repo.request(
              'PATCH',
              '/notifications/${n['id']}/read',
              {},
            );
          }
          if (!mounted) return;
          setState(
            () => n['readAt'] = widget.repo.now.toUtc().toIso8601String(),
          );
          if (n['orderId'] != null) {
            context.push(
              widget.repo.role == 'member'
                  ? '/member/orders/${n['orderId']}'
                  : '/orders/${n['orderId']}',
            );
          }
        } catch (e) {
          if (mounted) toast(context, e);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (player != null)
              PlayerArt(
                repo: widget.repo,
                player: player,
                width: 30,
                height: 32,
                radius: 9,
              )
            else
              Container(
                width: 30,
                height: 32,
                decoration: BoxDecoration(
                  color: unread ? ink : sage,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  unread ? CupertinoIcons.bell_fill : CupertinoIcons.bell,
                  size: 14,
                  color: unread ? Colors.white : muted,
                ),
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${n['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typeBodySmall.copyWith(
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        when(n['createdAt'], onlyTime: true),
                        style: typeCaption,
                      ),
                      if (unread) ...[
                        const SizedBox(width: 5),
                        Semantics(
                          label: '未读',
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${n['body'] ?? n['message'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typeSecondary.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 3, left: 2),
              child: Icon(
                CupertinoIcons.chevron_forward,
                size: 11,
                color: faint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.repo.notifications
        .where((n) => n['readAt'] == null)
        .length;
    final empty =
        !loading &&
        error == null &&
        widget.repo.notifications.isEmpty &&
        (!widget.repo.isProduction || widget.repo.token != null);
    return ClubPage(
      repo: widget.repo,
      title: '通知',
      child: loading && widget.repo.notifications.isEmpty
          ? const ClubSkeleton(kind: SkeletonKind.notifications)
          : PageList(
              children: [
                if (loading) const LinearProgressIndicator(minHeight: 2),
                if (error != null)
                  EmptyState(
                    '暂时无法获取通知',
                    error!,
                    action: TextButton(
                      onPressed: loading ? null : load,
                      child: const Text('重试'),
                    ),
                  ),
                if (widget.repo.isProduction && widget.repo.token == null)
                  EmptyState(
                    '登录后查看通知',
                    '订单安排和服务进度会显示在这里。',
                    action: FilledButton(
                      onPressed: () =>
                          context.push('/login?next=%2Fnotifications'),
                      child: const Text('前往登录'),
                    ),
                  ),
                if (!empty && widget.repo.notifications.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: ClubSegmentedControl(
                          values: const ['全部', '未读'],
                          value: filter,
                          onChanged: (v) => setState(() => filter = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${widget.repo.notifications.length} 条消息',
                        style: typeSecondary,
                      ),
                      const SizedBox(width: 8),
                      if (unread > 0) Tag('$unread 未读', fill: sage, color: ink),
                    ],
                  ),
                ],
                if (empty)
                  const EmptyState('暂时没有新通知', '预约安排和服务进度更新，会出现在这里。'),
                if (filter == '未读' && unread == 0 && !empty)
                  const EmptyState('没有未读通知', '切换回全部，查看已读消息。'),
                ...notificationGroups(),
                DemoStamp(widget.repo),
              ],
            ),
    );
  }
}

class SupportPage extends StatefulWidget {
  const SupportPage(this.repo, this.id, {super.key});
  final ClubRepository repo;
  final String id;
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final details = TextEditingController();
  String reason = '服务未按约定完成';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClubPage(
    repo: widget.repo,
    title: '申请售后',
    child: PageList(
      children: [
        const SizedBox(height: 4),
        const Text('把问题说清楚，\n俱乐部会跟进处理。', style: typeTitle),
        const SizedBox(height: 6),
        const Text(
          '提交后将暂停服务确认与相关结算。请提供客观事实，不要填写密码等敏感资料。',
          style: typeSecondary,
        ),
        const SizedBox(height: 16),
        const SectionTitle('问题信息', padding: EdgeInsets.only(bottom: 8)),
        DropdownButtonFormField<String>(
          initialValue: reason,
          style: const TextStyle(fontSize: 14, color: ink),
          decoration: const InputDecoration(labelText: '问题类型'),
          items: [
            '服务未按约定完成',
            '队友未按时到场',
            '服务内容与说明不符',
            '其他问题',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => reason = v!),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: details,
          maxLines: 5,
          maxLength: 1000,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            labelText: '发生了什么',
            hintText: '说明时间、具体问题与希望的处理方式',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              style: const TextStyle(color: danger, fontSize: 13),
            ),
          ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (details.text.trim().length < 5) {
                    setState(() => error = '请补充至少5个字的具体说明。');
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    final o = widget.repo.orders.firstWhere(
                      (o) => o['id'] == widget.id,
                    );
                    await widget.repo.orderAction(o, 'dispute', {
                      'reason': reason,
                      'details': details.text.trim(),
                    });
                    if (context.mounted) context.pop();
                  } catch (e) {
                    setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '正在提交…' : '提交售后申请'),
        ),
        const SizedBox(height: 10),
        const Text(
          '售后记录会同时保存到订单进度，处理结果由俱乐部同步。',
          style: TextStyle(fontSize: 11, color: muted, height: 1.5),
        ),
        DemoStamp(widget.repo),
      ],
    ),
  );
}

class PolicyPage extends StatelessWidget {
  const PolicyPage(this.repo, {super.key, required this.kind});
  final ClubRepository repo;
  final String kind;
  @override
  Widget build(BuildContext context) {
    final privacy = kind == 'privacy';
    return ClubPage(
      repo: repo,
      title: privacy ? '隐私政策' : '服务协议',
      child: PageList(
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              BrandMark(repo, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(repo.clubName, style: typeSection),
                    Text(
                      privacy ? '隐私政策 · 演示文本' : '服务协议 · 演示文本',
                      style: typeCaption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Surface(
            border: true,
            child: SelectableText(
              '${repo.club[privacy ? 'privacyText' : 'termsText'] ?? '暂未配置，请联系俱乐部'}',
              style: typeBodySmall.copyWith(height: 1.8),
            ),
          ),
          DemoStamp(repo),
        ],
      ),
    );
  }
}
