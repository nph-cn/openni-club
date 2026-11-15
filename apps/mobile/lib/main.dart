import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'ui.dart';
import 'discover.dart';
import 'orders.dart';
import 'booking.dart';
import 'member.dart';
import 'accessibility.dart';
import 'auth.dart';
import 'loading.dart';

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
    padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Icon(Icons.cloud_off_rounded, size: 52, color: muted),
      ),
      const SizedBox(height: 28),
      const Text(
        '暂时无法连接',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text('请检查网络连接后重试', style: TextStyle(fontSize: 16, color: muted)),
      const SizedBox(height: 32),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新加载'),
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
  });
  final ClubRepository repository;
  final String initialScreen;
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
          'orders_empty': '/states/orders-empty',
          'orders_guest': '/states/orders-guest',
          'privacy': '/legal/privacy',
          'terms': '/legal/terms',
          'home_android': '/',
          'services': '/services',
          'service': '/services/$serviceId',
          'service_120':
              '/services/$serviceId?variant=${serviceVariants(repo.services.firstOrNull ?? {}).lastOrNull?['id'] ?? ''}',
          'players': '/players',
          'player': '/players/$playerId',
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
          'delivery':
              '/member/orders/${repo.memberOrders.where((o) => stage(o) == 'in_progress').firstOrNull?['id'] ?? 'none'}?delivery=1',
          'availability': '/member/availability',
          'earnings': '/member/earnings',
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
            path: '/states/loading',
            builder: (_, _) => ClubPage(
              repo: repo,
              appBar: false,
              child: const ClubSkeleton(kind: SkeletonKind.home),
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
            ),
          ),
        ),
        GoRoute(
          path: '/players',
          builder: (_, _) => live(() => PlayersPage(repo)),
        ),
        GoRoute(
          path: '/players/:id',
          builder: (_, s) =>
              live(() => PlayerPage(repo, s.pathParameters['id']!)),
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
          ? clubTheme(repo).copyWith(platform: TargetPlatform.android)
          : clubTheme(repo),
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
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: title == '修改昵称' ? 30 : 100,
            ),
            const SizedBox(height: 14),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    BrandMark(repo, size: 58),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repo.token == null ? '未登录' : repo.memberName,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            repo.role == 'member'
                                ? '俱乐部成员'
                                : repo.token == null
                                ? '未登录'
                                : '俱乐部客户',
                            style: const TextStyle(color: muted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Surface(
                  color: sage,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${repo.orders.length}',
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(
                              '我的预约',
                              style: TextStyle(fontSize: 14, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${repo.following.length}',
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(
                              '本机关注',
                              style: TextStyle(fontSize: 14, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (busy) const LinearProgressIndicator(),
              if (repo.token == null && !settings) ...[
                FilledButton(
                  onPressed: busy ? null : login,
                  child: const Text('登录 / 注册'),
                ),
              ],
              if (settings && (repo.isLocal || repo.token != null)) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('修改昵称'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: busy
                      ? null
                      : () => edit('修改昵称', repo.memberName, repo.rename),
                ),
                if (!repo.isLocal && repo.role != 'member')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('接受成员邀请'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy
                        ? null
                        : () => edit('输入俱乐部邀请码', '', repo.acceptInvitation),
                  ),
              ],
              if (!settings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('我的预约'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/orders'),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/legal/privacy'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: const Text('服务与退款说明'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/legal/terms'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.headset_mic_outlined),
                title: const Text('联系俱乐部'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => textSheet(
                  context,
                  '联系俱乐部',
                  '${repo.club['supportContact'] ?? '请通过运营方公示渠道联系。'}',
                ),
              ),
              if (!settings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('设置与关于'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings'),
                ),
              if (settings && !repo.isProduction) ...[
                const Divider(),
                const Text(
                  '关于当前预览',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  '俱乐部、成员、订单与金额为示例资料，不提供真实服务或收款。人物为原创虚构形象；游戏图片来自发行商，版权归原权利人。',
                  style: TextStyle(fontSize: 14, color: muted, height: 1.65),
                ),
                const SizedBox(height: 16),
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
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_remove_outlined),
                  title: Text(repo.isLocal ? '清除本地数据' : '注销账号'),
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
                                  onPressed: () => Navigator.pop(ctx, false),
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
                              if (context.mounted) toast(context, '资料已清除。');
                            } catch (e) {
                              if (context.mounted) toast(context, e);
                            }
                          }
                        },
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: repo.clubName,
                  ),
                  child: const Text('OpenNI · 开源许可'),
                ),
              ],
            ],
          ),
  );
}

class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  Widget build(BuildContext context) => ClubPage(
    repo: repo,
    title: '俱乐部动态',
    child: repo.announcements.isEmpty
        ? const EmptyState('暂无公告', '俱乐部发布的通知会显示在这里')
        : PageList(
            children: repo.announcements
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            when(a['publishedAt']),
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${a['title']}',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${a['body']}',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 16,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
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

  @override
  Widget build(BuildContext context) => ClubPage(
    repo: widget.repo,
    title: '通知',
    child: loading && widget.repo.notifications.isEmpty
        ? const ClubSkeleton(kind: SkeletonKind.notifications)
        : PageList(
            children: [
              if (loading) const LinearProgressIndicator(),
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
              if (!loading &&
                  error == null &&
                  widget.repo.notifications.isEmpty &&
                  (!widget.repo.isProduction || widget.repo.token != null))
                const EmptyState('暂时没有新通知', '预约安排和服务进度更新，会出现在这里。'),
              ...widget.repo.notifications.map(
                (n) => ListTile(
                  title: Text('${n['title']}'),
                  subtitle: Text('${n['body'] ?? n['message'] ?? ''}'),
                  onTap: () async {
                    try {
                      if (!widget.repo.isLocal) {
                        await widget.repo.request(
                          'PATCH',
                          '/notifications/${n['id']}/read',
                          {},
                        );
                      }
                      if (context.mounted && n['orderId'] != null) {
                        context.push(
                          widget.repo.role == 'member'
                              ? '/member/orders/${n['orderId']}'
                              : '/orders/${n['orderId']}',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) toast(context, e);
                    }
                  },
                ),
              ),
            ],
          ),
  );
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
        const Text(
          '把问题说清楚，\n俱乐部会跟进处理。',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          '提交后将暂停服务确认与相关结算。请提供客观事实，不要填写密码等敏感资料。',
          style: TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          initialValue: reason,
          decoration: const InputDecoration(labelText: '问题类型'),
          items: [
            '服务未按约定完成',
            '队友未按时到场',
            '服务内容与说明不符',
            '其他问题',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => reason = v!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: details,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: '发生了什么',
            hintText: '说明时间、具体问题与希望的处理方式',
          ),
        ),
        const SizedBox(height: 20),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
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
          const SizedBox(height: 16),
          Text(
            repo.clubName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          SelectableText(
            '${repo.club[privacy ? 'privacyText' : 'termsText'] ?? '暂未配置，请联系俱乐部'}',
            style: const TextStyle(fontSize: 16, height: 1.8, color: ink),
          ),
        ],
      ),
    );
  }
}
