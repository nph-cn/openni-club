import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'repository.dart';
import 'ui.dart';
import 'loading.dart';

String priceUnit(Json s) => s['billingUnit'] == 'hour'
    ? (s['durationMinutes'] == 60 ? '小时' : '套餐')
    : const {'session': '场', 'target': '单'}[s['billingUnit']] ?? '场';
String serviceKind(Json s) =>
    const {
      'hourly': '小时陪练',
      'escort': '护航',
      'review': '对局复盘',
    }[s['serviceType']] ??
    '${s['category'] ?? ''}';
List<String> serviceFacts(Json s) => [
  if (s['platform'] != null) s['platform'] == 'mobile' ? '手游' : '端游',
  if ('${s['gameMode'] ?? ''}'.isNotEmpty) '${s['gameMode']}',
  if (s['teamSize'] != null) '${s['teamSize']} 位陪练',
];

Json? serviceForGame(ClubRepository repo, String? game) => repo.services
    .where((service) => '${service['game']}' == '$game')
    .firstOrNull;

Json? sceneForPlayer(ClubRepository repo, Json player) {
  for (final game in (player['games'] as List? ?? [])) {
    final service = serviceForGame(repo, '$game');
    if (service != null) return service;
  }
  return repo.services.firstOrNull;
}

/// Number of players that can serve the games of a service.
List<Json> playersForService(ClubRepository repo, Json service) => repo.players
    .where((player) => (player['games'] as List? ?? []).contains(service['game']))
    .toList();

String greetingFor(DateTime now) {
  final hour = now.toUtc().add(const Duration(hours: 8)).hour;
  if (hour < 11) return '早上好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? selectedGame;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final games = repo.services.map((s) => '${s['game']}').toSet().toList();
    selectedGame ??= games.firstOrNull;
    final services = repo.services
        .where((s) => s['game'] == selectedGame)
        .toList();
    final players = repo.players
        .where((p) => (p['games'] as List).contains(selectedGame))
        .toList();
    final active = repo.orders
        .where((o) => !['completed', 'cancelled'].contains(stage(o)))
        .firstOrNull;
    final recent = [...repo.orders]
      ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    final unread = repo.notifications.where((n) => n['readAt'] == null).length;
    return ClubPage(
      repo: repo,
      tab: 0,
      appBar: false,
      child: PageList(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
        children: [
          Row(
            children: [
              BrandMark(repo, size: 32),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repo.clubName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typeBodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${greetingFor(repo.now)}，今天想练哪一局？',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typeSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HomeIconButton(
                icon: CupertinoIcons.bell,
                tooltip: '通知',
                badge: unread,
                onTap: () => context.push('/notifications'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SearchEntry(onTap: () => context.go('/services')),
          if (active != null) ...[
            const SizedBox(height: 12),
            _ActiveServiceCard(repo: repo, order: active),
          ],
          if (repo.banners.isNotEmpty) ...[
            const SizedBox(height: 14),
            HomeBanners(repo),
          ] else if (services.isNotEmpty) ...[
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 2.2,
              child: ServiceArt(services.first, radius: 16, banner: true),
            ),
          ],
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final game in games) ...[
                  GameSelector(
                    service: repo.services.firstWhere((s) => s['game'] == game),
                    selected: selectedGame == game,
                    onTap: () => setState(() => selectedGame = game),
                  ),
                  if (game != games.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          SectionTitle(
            '精选服务',
            caption: selectedGame == null ? null : '$selectedGame · 官方目录',
            action: '全部',
            onTap: () => context.go(
              '/services?game=${Uri.encodeComponent(selectedGame ?? '全部')}',
            ),
          ),
          if (services.isEmpty)
            const Text('暂无服务', style: typeSecondary)
          else
            for (final service in services)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ServiceFeature(
                  repo: repo,
                  service: service,
                  poster: true,
                ),
              ),
          SectionTitle(
            '推荐陪练',
            caption: '按擅长游戏与可约档期展示',
            action: '全部',
            onTap: () => context.push('/players'),
          ),
          if (players.isEmpty)
            const Text('暂无陪练', style: typeSecondary)
          else
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: players.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                    PlayerRailCard(repo: repo, player: players[i]),
              ),
            ),
          SectionTitle(
            '俱乐部公告',
            action: '全部',
            onTap: () => context.push('/announcements'),
          ),
          if (repo.announcements.isEmpty)
            Surface(
              border: true,
              child: Row(
                children: [
                  const Icon(
                    Icons.campaign_outlined,
                    size: 18,
                    color: faint,
                  ),
                  const SizedBox(width: 10),
                  Text('暂无公告', style: typeSecondary),
                ],
              ),
            )
          else
            GroupCard(
              children: [
                for (final a in repo.announcements.take(2))
                  GroupRow(
                    leading: const Icon(
                      Icons.campaign_outlined,
                      size: 17,
                      color: muted,
                    ),
                    title: '${a['title']}',
                    subtitle: when(a['publishedAt']),
                    onTap: () => context.push('/announcements'),
                  ),
              ],
            ),
          SectionTitle(
            '最近订单',
            action: '全部',
            onTap: () => context.go('/orders'),
          ),
          if (recent.isEmpty)
            EmptyState('还没有预约', '选一项服务，约上想一起打的队友。')
          else
            GroupCard(
              children: [
                for (final order in recent.take(3))
                  _RecentOrderRow(repo: repo, order: order),
              ],
            ),
          DemoStamp(repo),
        ],
      ),
    );
  }
}

class _HomeIconButton extends StatelessWidget {
  const _HomeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18),
              if (badge > 0)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 12),
                    height: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: danger,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 8,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: rule, width: .6),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 17, color: faint),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              '搜索游戏、服务或陪练',
              style: TextStyle(fontSize: 14, color: faint),
            ),
          ),
          Container(width: .6, height: 14, color: rule),
          const SizedBox(width: 8),
          const Icon(Icons.tune_rounded, size: 16, color: muted),
        ],
      ),
    ),
  );
}

class _ActiveServiceCard extends StatelessWidget {
  const _ActiveServiceCard({required this.repo, required this.order});
  final ClubRepository repo;
  final Json order;
  @override
  Widget build(BuildContext context) {
    final service =
        repo.findService('${order['serviceId']}') ??
        Json.from(order['serviceSnapshot'] as Map? ?? const {});
    final player = repo.findPlayer(
      '${order['assignedPlayerId'] ?? order['playerId'] ?? ''}',
    );
    return InkWell(
      onTap: () => context.push('/orders/${order['id']}'),
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 116,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ServiceArt(service, radius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xE6161C25), Color(0xB0232C38), Color(0x660F141A)],
                    stops: [0, .6, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LiveDot(stage: stage(order)),
                        const SizedBox(width: 6),
                        Text(
                          stageName(stage(order)),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          when(order['scheduledAt']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xCFFFFFFF),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          CupertinoIcons.chevron_forward,
                          size: 12,
                          color: Color(0xB3FFFFFF),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${order['serviceTitle']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (player != null) ...[
                          PlayerArt(
                            repo: repo,
                            player: player,
                            width: 20,
                            height: 20,
                            radius: 10,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${player['name']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xE6FFFFFF),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            orderSpecification(order),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xBFFFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '查看进度',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: .92),
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
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.stage});
  final String stage;
  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: stage == 'in_progress'
          ? const Color(0xFF7BD8A4)
          : const Color(0xFFE8C87B),
      shape: BoxShape.circle,
    ),
  );
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.repo, required this.order});
  final ClubRepository repo;
  final Json order;
  @override
  Widget build(BuildContext context) {
    final service =
        repo.findService('${order['serviceId']}') ??
        Json.from(order['serviceSnapshot'] as Map? ?? const {});
    return InkWell(
      onTap: () => context.push('/orders/${order['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: ServiceArt(service, radius: 11),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order['serviceTitle']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      StagePill(stage(order), compact: true),
                      const SizedBox(width: 6),
                      Text(when(order['scheduledAt']), style: typeSecondary),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PriceText(money(order), size: 14),
            const SizedBox(width: 2),
            const Icon(CupertinoIcons.chevron_forward, size: 13, color: faint),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner carousel: operator-configured imagery, no invented campaigns.
// ---------------------------------------------------------------------------
class HomeBanners extends StatefulWidget {
  const HomeBanners(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<HomeBanners> createState() => _HomeBannersState();
}

class _HomeBannersState extends State<HomeBanners> {
  int page = 0;
  final controller = PageController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void next() {
    final next = (page + 1) % widget.repo.banners.length;
    final media = MediaQuery.of(context);
    if (media.reduceMotion || media.disableAnimations) {
      controller.jumpToPage(next);
    } else {
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2.15,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: widget.repo.banners.length,
            onPageChanged: (v) => setState(() => page = v),
            itemBuilder: (context, i) {
              final banner = widget.repo.banners[i];
              return InkWell(
                onTap: () {
                  final id = '${banner['serviceId'] ?? ''}';
                  if (widget.repo.findService(id) != null) {
                    context.push('/services/$id');
                  } else {
                    context.go(
                      '/services?game=${Uri.encodeComponent('${banner['game'] ?? '全部'}')}',
                    );
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ServiceArt({
                      'coverUrl': banner['imageUrl'],
                      'game': banner['game'],
                    }, radius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x1A0B0F14),
                            Color(0x330B0F14),
                            Color(0xE60B0F14),
                          ],
                          stops: [0, .45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${banner['game'] ?? '俱乐部精选'}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${banner['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (widget.repo.banners.length > 1) ...[
            Positioned(
              top: 9,
              right: 9,
              child: Tooltip(
                message: '下一张横幅',
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0x660F141A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(
                        color: Color(0x40FFFFFF),
                        width: .6,
                      ),
                    ),
                  ),
                  onPressed: next,
                  child: Text(
                    '${page + 1} / ${widget.repo.banners.length}',
                    semanticsLabel:
                        '下一张横幅，当前第 ${page + 1} 张，共 ${widget.repo.banners.length} 张',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 5,
              child: Row(
                children: List.generate(
                  widget.repo.banners.length,
                  (i) => AnimatedContainer(
                    duration:
                        MediaQuery.of(context).disableAnimations ||
                            MediaQuery.of(context).reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 4),
                    width: i == page ? 14 : 4,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: i == page ? 1 : .4,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Game category tile
// ---------------------------------------------------------------------------
class GameSelector extends StatelessWidget {
  const GameSelector({
    super.key,
    required this.service,
    required this.selected,
    required this.onTap,
  });
  final Json service;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${service['game']}',
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: selected ? ink : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ServiceArt(service, radius: 0),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              ink.withValues(alpha: selected ? .55 : .35),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 5,
                        right: 4,
                        bottom: 4,
                        child: Text(
                          '${service['game']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${service['game']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: selected ? ink : muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Compact photo card used by the home recommendation rail.
class PlayerRailCard extends StatelessWidget {
  const PlayerRailCard({super.key, required this.repo, required this.player});
  final ClubRepository repo;
  final Json player;
  @override
  Widget build(BuildContext context) {
    final prices =
        repo.services
            .where((s) => (player['games'] as List).contains(s['game']))
            .expand(
              (s) => serviceVariants(s).isEmpty ? [s] : serviceVariants(s),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['priceCents'] as int).compareTo(b['priceCents'] as int),
          );
    return SizedBox(
      width: 148,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/players/${player['id']}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 152,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlayerArt(
                      repo: repo,
                      player: player,
                      radius: 0,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00000000),
                            Color(0x12000000),
                            Color(0xB3000000),
                          ],
                          stops: [0, .55, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 9,
                      right: 9,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${player['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${player['role']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xD9FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (prices.isNotEmpty)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCCFFFFFF),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '¥${money(prices.first)} 起',
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (player['tags'] as List? ?? []).take(2).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typeCaption,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (player['games'] as List).join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typeSecondary,
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_forward,
                          size: 11,
                          color: faint,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service cards
// ---------------------------------------------------------------------------
class ServiceFeature extends StatelessWidget {
  const ServiceFeature({
    super.key,
    required this.repo,
    required this.service,
    this.embedded = false,
    this.poster = false,
    this.playerId,
    this.variantId,
  });
  final ClubRepository repo;
  final Json service;
  final bool embedded, poster;
  final String? playerId, variantId;
  @override
  Widget build(BuildContext context) {
    final variants = serviceVariants(service);
    final lowest = variants.isEmpty
        ? service
        : variants.reduce((a, b) => a['priceCents'] < b['priceCents'] ? a : b);
    final requestedVariant = variants
        .where((v) => v['id'] == variantId)
        .firstOrNull;
    final quote = {...service, ...(requestedVariant ?? lowest)};
    final priceLabel = requestedVariant == null && variants.length > 1
        ? '¥${money(quote)} 起'
        : '¥${money(quote)}';
    final facts = serviceFacts(quote);
    void open() => context.push(
      Uri(
        path: '/services/${service['id']}',
        queryParameters: {'player': ?playerId, 'variant': ?variantId},
      ).toString(),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${service['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 13,
              color: faint,
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${service['description']}',
          maxLines: poster ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: typeSecondary,
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  quote['durationMinutes'] == null
                      ? null
                      : '${quote['durationMinutes']}分钟',
                  serviceKind(quote),
                  ...facts.take(1),
                ].whereType<String>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typeCaption,
              ),
            ),
            const SizedBox(width: 6),
            PriceText(
              money(quote),
              size: 15,
              unit: requestedVariant == null && variants.length > 1
                  ? ' 起'
                  : '/${priceUnit(quote)}',
            ),
          ],
        ),
      ],
    );
    if (embedded) {
      return InkWell(onTap: open, child: heading);
    }
    if (poster) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ServiceArt(service, radius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x73000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Row(
                        children: [
                          _PhotoBadge('${service['game']}'),
                          const SizedBox(width: 5),
                          _PhotoBadge(serviceKind(quote)),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 9,
                      child: Text(
                        priceLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 11, 11),
                child: heading,
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 88,
                child: ServiceArt(service, radius: 11),
              ),
              const SizedBox(width: 11),
              Expanded(child: heading),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(
      color: const Color(0x73000000),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0x26FFFFFF), width: .5),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

/// Catalog media stays at its original HTTPS source. Copyright belongs to its owner.
class ServiceArt extends StatelessWidget {
  const ServiceArt(
    this.service, {
    super.key,
    this.radius = 14,
    this.icon = false,
    this.banner = false,
  });
  final Json service;
  final double radius;
  final bool icon, banner;
  @override
  Widget build(BuildContext context) {
    final field = icon
        ? 'gameIconUrl'
        : banner
        ? 'bannerUrl'
        : 'coverUrl';
    final url = '${service[field] ?? service['coverUrl'] ?? ''}';
    final game = '${service['game'] ?? ''}'.trim();
    final fallback = _ArtFallback(game: game, icon: icon, radius: radius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(
        child: url.startsWith('https://')
            ? Image.network(
                url,
                fit: icon ? BoxFit.contain : BoxFit.cover,
                filterQuality: FilterQuality.medium,
                alignment: Alignment.center,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                    frame != null || wasSynchronouslyLoaded
                    ? child
                    : SkeletonPulse(
                        child: SkeletonBlock(
                          width: double.infinity,
                          height: double.infinity,
                          radius: radius,
                        ),
                      ),
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback({
    required this.game,
    required this.icon,
    required this.radius,
  });
  final String game;
  final bool icon;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final seed = game.isEmpty ? 3 : game.codeUnits.fold(0, (a, b) => a + b);
    const tones = [
      [Color(0xFF33404F), Color(0xFF171C23)],
      [Color(0xFF3D4A3C), Color(0xFF1B211B)],
      [Color(0xFF4A3E46), Color(0xFF211B1F)],
      [Color(0xFF38424F), Color(0xFF181D24)],
    ];
    final tone = tones[seed % tones.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tone,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            game.isEmpty ? '游戏服务' : game,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: icon ? 10 : 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
              color: Colors.white.withValues(alpha: .72),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Roster row in the player directory
// ---------------------------------------------------------------------------
class RosterRow extends StatelessWidget {
  const RosterRow({super.key, required this.repo, required this.player});
  final ClubRepository repo;
  final Json player;
  @override
  Widget build(BuildContext context) {
    final prices =
        repo.services
            .where((s) => (player['games'] as List).contains(s['game']))
            .expand(
              (s) => serviceVariants(s).isEmpty ? [s] : serviceVariants(s),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['priceCents'] as int).compareTo(b['priceCents'] as int),
          );
    final followed = repo.following.contains('${player['id']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/players/${player['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlayerArt(
                  repo: repo,
                  player: player,
                  width: 66,
                  height: 76,
                  radius: 12,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${player['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typeBodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: followed
                                ? '取消关注 ${player['name']}'
                                : '关注 ${player['name']}',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => repo.toggleFollow(
                              '${player['id']}',
                            ),
                            icon: Icon(
                              followed
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 17,
                              color: followed ? danger : faint,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${player['role']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typeSecondary,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          for (final tag in (player['tags'] as List? ?? []).take(2))
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Tag(
                                '$tag',
                                fill: sage,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (player['games'] as List).join(' / '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typeCaption,
                            ),
                          ),
                          if (prices.isNotEmpty)
                            Text(
                              '¥${money(prices.first)} 起',
                              style: typeLabel.copyWith(
                                fontSize: 13,
                                color: stageTone('in_progress'),
                              ),
                            ),
                          const SizedBox(width: 2),
                          const Icon(
                            CupertinoIcons.chevron_forward,
                            size: 12,
                            color: faint,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.repo, required this.player});
  final ClubRepository repo;
  final Json player;
  @override
  Widget build(BuildContext context) => RosterRow(repo: repo, player: player);
}

// ---------------------------------------------------------------------------
// Find a player / service directory
// ---------------------------------------------------------------------------
class ServicesPage extends StatefulWidget {
  const ServicesPage(this.repo, {super.key, this.initialGame = '全部'});
  final ClubRepository repo;
  final String initialGame;
  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  late String game = widget.initialGame;
  String query = '', section = '游戏服务';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServicesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGame != widget.initialGame) game = widget.initialGame;
  }

  Widget sectionPicker() => ClubSegmentedControl(
    values: const ['游戏服务', '俱乐部陪练'],
    value: section,
    onChanged: (next) {
      FocusScope.of(context).unfocus();
      setState(() => section = next);
    },
  );

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, term = query.trim().toLowerCase();
    final items = repo.services
        .where(
          (s) =>
              (game == '全部' || s['game'] == game) &&
              '${s['title']} ${s['game']} ${s['description']}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();
    return ClubPage(
      repo: repo,
      title: '找陪练',
      tab: 1,
      // 离屏目录保留搜索与滚动状态，同时退出焦点和辅助功能遍历。
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: section != '游戏服务',
            child: TickerMode(
              enabled: section == '游戏服务',
              child: PageList(
                key: const PageStorageKey('service-directory'),
                children: [
                  sectionPicker(),
                  const SizedBox(height: 12),
                  ClubSearchField(
                    controller: search,
                    hintText: '搜索游戏或服务',
                    onChanged: (v) => setState(() => query = v),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    onClear: () {
                      search.clear();
                      setState(() => query = '');
                    },
                  ),
                  const SizedBox(height: 10),
                  _DirectoryGames(
                    games: repo.services
                        .map((s) => '${s['game']}')
                        .toSet()
                        .toList(),
                    selected: game,
                    onSelected: (v) => setState(() => game = v),
                  ),
                  const SizedBox(height: 10),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            '${items.length} 项服务',
                            style: typeSecondary,
                          ),
                          const Spacer(),
                          const Icon(
                            CupertinoIcons.arrow_up_arrow_down,
                            size: 12,
                            color: faint,
                          ),
                          const SizedBox(width: 4),
                          Text('按目录顺序', style: typeCaption),
                        ],
                      ),
                    ),
                  if (items.isEmpty)
                    EmptyState(
                      '没有匹配的服务',
                      '试试其他游戏或关键词。',
                      action: OutlinedButton(
                        onPressed: () {
                          search.clear();
                          setState(() {
                            query = '';
                            game = '全部';
                          });
                        },
                        child: const Text('清除筛选'),
                      ),
                    ),
                  for (final service in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ServiceFeature(repo: repo, service: service),
                    ),
                ],
              ),
            ),
          ),
          Offstage(
            offstage: section != '俱乐部陪练',
            child: TickerMode(
              enabled: section == '俱乐部陪练',
              child: PlayerDirectory(
                repo,
                key: const PageStorageKey('player-directory'),
                initialGame: widget.initialGame,
                header: sectionPicker(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryGames extends StatelessWidget {
  const _DirectoryGames({
    required this.games,
    required this.selected,
    required this.onSelected,
    this.leading,
  });
  final List<String> games;
  final String selected;
  final ValueChanged<String> onSelected;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 10),
          Container(width: .6, height: 18, color: rule),
          const SizedBox(width: 10),
        ],
        for (final v in ['全部', ...games.where((v) => v.trim().isNotEmpty)])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              selected: selected == v,
              label: Text(
                v == '全部' ? '全部游戏' : v,
                style: const TextStyle(fontSize: 13),
              ),
              onSelected: (_) => onSelected(v),
            ),
          ),
      ],
    ),
  );
}

/// 陪练目录仅筛选服务端目录和本机关注，不推断在线状态或排序业绩。
class PlayerDirectory extends StatefulWidget {
  const PlayerDirectory(
    this.repo, {
    super.key,
    this.initialGame = '全部',
    this.onlyFollowing = false,
    this.header,
  });
  final ClubRepository repo;
  final String initialGame;
  final bool onlyFollowing;
  final Widget? header;
  @override
  State<PlayerDirectory> createState() => _PlayerDirectoryState();
}

class _PlayerDirectoryState extends State<PlayerDirectory> {
  final search = TextEditingController();
  late String game = widget.initialGame;
  late bool following = widget.onlyFollowing;
  String query = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGame != widget.initialGame) game = widget.initialGame;
    if (oldWidget.onlyFollowing != widget.onlyFollowing) {
      following = widget.onlyFollowing;
    }
  }

  void clearFilters() {
    search.clear();
    setState(() {
      query = '';
      game = '全部';
      following = false;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repo,
    builder: (context, _) {
      final repo = widget.repo, term = query.trim().toLowerCase();
      final games = repo.players
          .expand((p) => (p['games'] as List? ?? []).map((v) => '$v'))
          .toSet()
          .toList();
      final items = repo.players.where((p) {
        final playerGames = (p['games'] as List? ?? [])
            .map((v) => '$v')
            .toList();
        final searchable =
            '${p['name'] ?? ''} ${p['role'] ?? ''} ${playerGames.join(' ')}'
                .toLowerCase();
        return (game == '全部' || playerGames.contains(game)) &&
            (!following || repo.following.contains('${p['id']}')) &&
            searchable.contains(term);
      }).toList();
      final hasFiltered = following || game != '全部' || term.isNotEmpty;
      return PageList(
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 12),
          ],
          ClubSearchField(
            controller: search,
            hintText: '搜索姓名、角色或游戏',
            onChanged: (v) => setState(() => query = v),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            onClear: () {
              search.clear();
              setState(() => query = '');
            },
          ),
          const SizedBox(height: 10),
          _DirectoryGames(
            games: games,
            selected: game,
            onSelected: (v) => setState(() => game = v),
            leading: FilterChip(
              selected: following,
              showCheckmark: false,
              avatar: Icon(
                following
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                size: 15,
                color: following ? onBrand(repo) : muted,
              ),
              label: Text(
                '本机关注',
                style: TextStyle(
                  fontSize: 13,
                  color: following ? onBrand(repo) : ink,
                ),
              ),
              onSelected: (v) => setState(() => following = v),
            ),
          ),
          const SizedBox(height: 10),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${items.length} 位陪练', style: typeSecondary),
            ),
          if (items.isEmpty)
            EmptyState(
              following && term.isEmpty && game == '全部'
                  ? '还没有本机关注'
                  : hasFiltered
                  ? '没有匹配的陪练'
                  : '暂无陪练',
              following && term.isEmpty && game == '全部'
                  ? '在陪练主页点击爱心，即可在这里找到。'
                  : hasFiltered
                  ? '试试其他游戏或关键词。'
                  : '俱乐部发布的陪练会显示在这里。',
              action: hasFiltered
                  ? OutlinedButton(
                      onPressed: clearFilters,
                      child: Text(following ? '查看全部陪练' : '清除筛选'),
                    )
                  : null,
            ),
          for (final player in items) RosterRow(repo: repo, player: player),
          DemoStamp(repo),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Service detail
// ---------------------------------------------------------------------------
class ServicePage extends StatefulWidget {
  const ServicePage(
    this.repo,
    this.id, {
    super.key,
    this.initialVariant,
    this.playerId,
  });
  final ClubRepository repo;
  final String id;
  final String? initialVariant;
  final String? playerId;
  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  String? variantId;
  int gallery = 0;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, service = widget.repo.findService(widget.id);
    if (service == null) {
      return ClubPage(
        repo: repo,
        title: '服务详情',
        child: const EmptyState('服务暂不可用', '请选择其他服务。'),
      );
    }
    final variants = serviceVariants(service);
    variantId ??= widget.initialVariant ?? variants.firstOrNull?['id'];
    final s = selectedService(service, variantId);
    final players = playersForService(repo, s);
    final siblings = repo.services
        .where((v) => v['game'] == s['game'] && v['id'] != service['id'])
        .toList();
    final scenes = [
      '${service['coverUrl'] ?? ''}',
      if (siblings.isNotEmpty) '${siblings.first['coverUrl'] ?? ''}',
      '${service['bannerUrl'] ?? ''}',
    ].where((url) => url.startsWith('https://')).toList();
    final inclusions = s['inclusions'] as List? ?? [],
        rules = s['rules'] as List? ?? [],
        requirements = s['requirements'] as List? ?? [];
    final multiple = (s['teamSize'] as num? ?? 1) > 1;
    return ClubPage(
      repo: repo,
      title: '服务详情',
      bottom: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PriceText(
                  money(s),
                  size: 22,
                  unit: '/${priceUnit(s)}',
                ),
                Text('${s['durationMinutes']} 分钟 · 示例价格', style: typeCaption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: multiple
                  ? null
                  : () => context.push(
                      Uri(
                        path: '/book',
                        queryParameters: {
                          'service': '${service['id']}',
                          'variant': ?variantId,
                          if (widget.playerId != null &&
                              players.any((p) => p['id'] == widget.playerId))
                            'player': widget.playerId!,
                        },
                      ).toString(),
                    ),
              child: Text(multiple ? '暂不支持多人单' : '立即预约'),
            ),
          ),
        ],
      ),
      child: PageList(
        children: [
          SizedBox(
            height: 206,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ServiceArt(service, radius: 16),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x26000000), Color(0x00000000), Color(0xB3000000)],
                      stops: [0, .45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x8C000000),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0x33FFFFFF),
                            width: .5,
                          ),
                        ),
                        child: Text(
                          '${s['game']} · ${serviceKind(s)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s['title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (scenes.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '${gallery + 1}/${scenes.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xD9FFFFFF),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (scenes.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  for (final entry in scenes.indexed) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => gallery = entry.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: gallery == entry.$1 ? ink : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                          padding: const EdgeInsets.all(1.5),
                          child: ServiceArt(
                            {
                              'coverUrl': entry.$2,
                              'game': s['game'],
                            },
                            radius: 7,
                          ),
                        ),
                      ),
                    ),
                    if (entry.$1 != scenes.length - 1)
                      const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: ServiceArt(service, radius: 10, icon: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${serviceFacts(s).isEmpty ? s['game'] : serviceFacts(s).join(' · ')}',
                      style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (s['tags'] as List? ?? []).join(' · '),
                      style: typeSecondary,
                    ),
                  ],
                ),
              ),
              for (final map in (s['maps'] as List? ?? []).take(1))
                Tag('$map', fill: sage, color: muted),
            ],
          ),
          if ('${s['description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${s['description']}',
              style: typeBodySmall.copyWith(height: 1.6, color: muted),
            ),
          ],
          if (variants.isNotEmpty) ...[
            const SectionTitle('选择规格'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: variants
                  .map(
                    (v) => ChoiceChip(
                      label: Text(
                        '${v['title']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      selected: variantId == v['id'],
                      onSelected: (_) => setState(() => variantId = v['id']),
                    ),
                  )
                  .toList(),
            ),
          ],
          if ((s['maps'] as List? ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.map,
                  size: 15,
                  color: muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '地图 ${(s['maps'] as List).join(' / ')}',
                    style: typeSecondary,
                  ),
                ),
              ],
            ),
          ],
          const SectionTitle('费用明细'),
          Surface(
            border: true,
            child: Column(
              children: [
                PairRow('服务单价', '¥${money(s)} / ${priceUnit(s)}'),
                PairRow('服务时长', '${s['durationMinutes']} 分钟'),
                PairRow('服务人数', '${s['teamSize'] ?? 1} 位陪练'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: .5, thickness: .5),
                ),
                PairRow('演示合计', '¥${money(s)}', strong: true),
              ],
            ),
          ),
          if (inclusions.isNotEmpty) ...[
            const SectionTitle('服务内容'),
            GroupCard(
              children: [
                for (final item in inclusions)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 15,
                          color: positive,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text('$item', style: typeBodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SectionTitle('可选陪练'),
          if (players.isEmpty)
            const Text('暂无陪练', style: typeSecondary)
          else
            GroupCard(
              children: [
                for (final p in players.take(3))
                  MemberRow(
                    repo: repo,
                    player: p,
                    serviceId: '${service['id']}',
                    variantId: variantId,
                  ),
              ],
            ),
          if (rules.isNotEmpty || requirements.isNotEmpty) ...[
            const SectionTitle('下单须知'),
            GroupCard(
              children: [
                for (final rule in [...rules, ...requirements])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(
                            CupertinoIcons.circle_fill,
                            size: 4,
                            color: faint,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '$rule',
                            style: typeSecondary.copyWith(
                              height: 1.5,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          DemoStamp(repo),
        ],
      ),
    );
  }
}

class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.repo,
    required this.player,
    this.trailing,
    this.serviceId,
    this.variantId,
  });
  final ClubRepository repo;
  final Json player;
  final Widget? trailing;
  final String? serviceId, variantId;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push(
      Uri(
        path: '/players/${player['id']}',
        queryParameters: {'service': ?serviceId, 'variant': ?variantId},
      ).toString(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          PlayerArt(
            repo: repo,
            player: player,
            width: 44,
            height: 48,
            radius: 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player['name']}',
                  style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  '${player['role']}',
                  style: typeSecondary,
                ),
              ],
            ),
          ),
          trailing ??
              const Icon(
                CupertinoIcons.chevron_forward,
                size: 13,
                color: faint,
              ),
        ],
      ),
    ),
  );
}

class PlayersPage extends StatelessWidget {
  const PlayersPage(
    this.repo, {
    super.key,
    this.initialGame = '全部',
    this.onlyFollowing = false,
  });
  final ClubRepository repo;
  final String initialGame;
  final bool onlyFollowing;
  @override
  Widget build(BuildContext context) => ClubPage(
    repo: repo,
    title: '俱乐部陪练',
    child: PlayerDirectory(
      repo,
      initialGame: initialGame,
      onlyFollowing: onlyFollowing,
    ),
  );
}

// ---------------------------------------------------------------------------
// Player profile
// ---------------------------------------------------------------------------
class PlayerPage extends StatefulWidget {
  const PlayerPage(
    this.repo,
    this.id, {
    super.key,
    this.serviceId,
    this.variantId,
  });
  final ClubRepository repo;
  final String id;
  final String? serviceId, variantId;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  List<Json>? slots;
  String? failure;
  int slotRequest = 0;

  Json? get contextService {
    final service = widget.repo.findService(widget.serviceId ?? '');
    final player = widget.repo.findPlayer(widget.id);
    if (service == null ||
        !(player?['games'] as List? ?? []).contains(service['game'])) {
      return null;
    }
    if (widget.variantId != null &&
        !serviceVariants(service).any((v) => v['id'] == widget.variantId)) {
      return null;
    }
    return service;
  }

  Json? get contextQuote {
    final service = contextService;
    if (service == null) return null;
    return selectedService(
      service,
      widget.variantId ?? serviceVariants(service).firstOrNull?['id'],
    );
  }

  @override
  void initState() {
    super.initState();
    loadSlots();
  }

  @override
  void didUpdateWidget(covariant PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.serviceId != widget.serviceId ||
        oldWidget.variantId != widget.variantId) {
      loadSlots();
    }
  }

  Future<void> bookPlayer(List<Json> services) async {
    final quote = contextQuote;
    Json? selection = quote == null
        ? null
        : {
            'service': '${quote['id']}',
            if (quote['variantId'] != null) 'variant': '${quote['variantId']}',
          };
    // 未从服务页选择具体规格时，由用户选择，不能静默预约第一项。
    selection ??= await showClubSheet<Json>(
      context: context,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          children: [
            const SheetHeading(
              '选择游戏服务',
              caption: '俱乐部会核对档期，最终以订单安排为准。',
            ),
            const SizedBox(height: 4),
            for (final service in services)
              for (final variant
                  in serviceVariants(service).isEmpty
                      ? [service]
                      : serviceVariants(service))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      enabled:
                          (variant['teamSize'] as num? ??
                              service['teamSize'] as num? ??
                              1) <=
                          1,
                      leading: SizedBox(
                        width: 42,
                        height: 42,
                        child: ServiceArt(service, radius: 9),
                      ),
                      title: Text(
                        '${service['title']}',
                        style: typeBodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${variant['id'] == service['id'] ? '${variant['durationMinutes']}分钟' : variant['title']} · ¥${money(variant)} / ${priceUnit({...service, ...variant})}',
                        style: typeSecondary,
                      ),
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 14,
                        color: faint,
                      ),
                      onTap: () => Navigator.pop(ctx, <String, dynamic>{
                        'service': '${service['id']}',
                        if (variant['id'] != service['id'])
                          'variant': '${variant['id']}',
                      }),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    context.push(
      Uri(
        path: '/book',
        queryParameters: {
          'service': '${selection['service']}',
          if (selection['variant'] != null)
            'variant': '${selection['variant']}',
          'player': widget.id,
        },
      ).toString(),
    );
  }

  Future<void> loadSlots() async {
    final request = ++slotRequest;
    setState(() {
      failure = null;
      slots = null;
    });
    try {
      final today = widget.repo.now.toUtc().add(const Duration(hours: 8));
      final value = await widget.repo.getAvailability(
        widget.id,
        DateTime(today.year, today.month, today.day + 1),
        (contextQuote?['durationMinutes'] as num?)?.toInt() ?? 60,
      );
      if (mounted && request == slotRequest) {
        setState(() {
          slots = value;
          failure = null;
        });
      }
    } catch (e) {
      if (mounted && request == slotRequest) setState(() => failure = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, p = widget.repo.findPlayer(widget.id);
    if (p == null) {
      return ClubPage(
        repo: repo,
        title: '陪练主页',
        child: const EmptyState('未找到这位陪练', '请返回陪练目录。'),
      );
    }
    final services = repo.services
        .where((s) => (p['games'] as List).contains(s['game']))
        .toList();
    final prices =
        services
            .expand(
              (s) => serviceVariants(s).isEmpty ? [s] : serviceVariants(s),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['priceCents'] as int).compareTo(b['priceCents'] as int),
          );
    final available = slots?.where((s) => s['available'] == true).toList();
    final quote = contextQuote;
    final selectedPrice = quote ?? prices.firstOrNull;
    final scene = sceneForPlayer(repo, p);
    final followed = repo.following.contains(widget.id);
    return ClubPage(
      repo: repo,
      title: '陪练主页',
      actions: [
        IconButton(
          tooltip: followed ? '取消关注' : '关注陪练',
          onPressed: () => repo.toggleFollow(widget.id),
          icon: Icon(
            followed ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 19,
            color: followed ? danger : ink,
          ),
        ),
      ],
      bottom: Row(
        children: [
          if (selectedPrice != null)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PriceText(
                    money(selectedPrice),
                    size: 22,
                    unit: quote == null ? ' 起' : '/${priceUnit(quote)}',
                  ),
                  Text(
                    quote == null ? '起价 · 示例价格' : '${quote['durationMinutes']} 分钟',
                    style: typeCaption,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed:
                  services.isEmpty || (quote?['teamSize'] as num? ?? 1) > 1
                  ? null
                  : () => bookPlayer(services),
              child: const Text('预约 TA'),
            ),
          ),
        ],
      ),
      child: PageList(
        children: [
          SizedBox(
            height: 218,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (scene != null) ServiceArt(scene, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Color(0x00000000),
                          Color(0xE6000000),
                        ],
                        stops: [0, .4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x8C000000),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0x33FFFFFF),
                              width: .5,
                            ),
                          ),
                          child: Text(
                            followed ? '已关注 · 俱乐部陪练' : '俱乐部陪练',
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: PlayerArt(
                      repo: repo,
                      player: p,
                      width: 72,
                      height: 84,
                      radius: 14,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 100,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['name']}',
                          style: const TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${p['role']}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            for (final game in (p['games'] as List))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '$game',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
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
          ),
          const SizedBox(height: 12),
          Surface(
            border: true,
            child: Row(
              children: [
                Expanded(
                  child: MetricBlock(
                    value: '${services.length}',
                    label: '在售服务',
                  ),
                ),
                Container(width: .5, height: 28, color: rule),
                Expanded(
                  child: MetricBlock(
                    value: prices.isEmpty ? '—' : '¥${money(prices.first)}',
                    label: '最低起价',
                  ),
                ),
                Container(width: .5, height: 28, color: rule),
                Expanded(
                  child: MetricBlock(
                    value: available == null
                        ? '…'
                        : '${available.length}',
                    label: '明日可约',
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('关于 TA'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (p['tags'] as List? ?? [])
                .map((v) => Tag('$v', fill: sage, color: muted))
                .toList(),
          ),
          const SizedBox(height: 9),
          Text(
            '${p['bio']}',
            style: typeBodySmall.copyWith(height: 1.65, color: muted),
          ),
          if (quote != null)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 14,
                    color: positive,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已选 ${quote['title']} · ${quote['variantTitle'] ?? '${quote['durationMinutes']}分钟'}',
                      style: typeSecondary,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.serviceId != null && quote == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '原服务或规格已不可用，请重新选择。',
                style: TextStyle(fontSize: 13, color: danger),
              ),
            ),
          SectionTitle('服务'),
          if (services.isEmpty)
            const Text('暂无服务', style: typeSecondary),
          for (final service in services)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ServiceFeature(
                repo: repo,
                service: service,
                playerId: widget.id,
                variantId: quote != null && service['id'] == quote['id']
                    ? quote['variantId'] as String?
                    : null,
              ),
            ),
          SectionTitle(
            '明日可约时段',
            caption: '按 ${quote?['durationMinutes'] ?? 60} 分钟查看 · 北京时间',
            action: failure != null ? '重试' : null,
            onTap: failure != null ? loadSlots : null,
          ),
          if (failure != null)
            Text('排班加载失败：$failure', style: typeSecondary)
          else if (slots == null)
            const ClubSkeleton(kind: SkeletonKind.slots)
          else if (available!.isEmpty)
            const Text('暂无时段', style: typeSecondary)
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: available
                  .take(6)
                  .map(
                    (s) => Container(
                      width: 74,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: rule, width: .6),
                      ),
                      child: Column(
                        children: [
                          Text(
                            when(s['startAt'], onlyTime: true),
                            style: typeNumber.copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 1),
                          Text('可预约', style: typeCaption),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 6),
          Text('时段来自俱乐部排班，演示模式按虚构规则生成。', style: typeCaption),
          DemoStamp(repo),
        ],
      ),
    );
  }
}
