import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
    return ClubPage(
      repo: repo,
      tab: 0,
      appBar: false,
      child: PageList(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Row(
            children: [
              BrandMark(repo, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  repo.clubName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '通知',
                style: IconButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => context.go('/services'),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: rule, width: .6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, size: 21, color: muted),
                  SizedBox(width: 9),
                  Text('搜索游戏或服务', style: TextStyle(fontSize: 15, color: muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InkWell(
                onTap: () => context.push('/orders/${active['id']}'),
                child: Surface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timelapse_rounded,
                        size: 18,
                        color: brandColor(repo),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        stageName(stage(active)),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${active['serviceTitle']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          if (repo.banners.isNotEmpty)
            HomeBanners(repo)
          else if (services.isNotEmpty)
            AspectRatio(
              aspectRatio: 2.25,
              child: ServiceArt(services.first, radius: 16, banner: true),
            ),
          const SizedBox(height: 20),
          Row(
            children: games
                .map(
                  (game) => Expanded(
                    child: GameSelector(
                      service: repo.services.firstWhere(
                        (s) => s['game'] == game,
                      ),
                      selected: selectedGame == game,
                      onTap: () => setState(() => selectedGame = game),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          SectionTitle(
            '游戏服务',
            action: '全部',
            onTap: () => context.go(
              '/services?game=${Uri.encodeComponent(selectedGame ?? '全部')}',
            ),
          ),
          if (services.isEmpty)
            const Text('暂无服务', style: TextStyle(color: muted))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in services.take(2).indexed) ...[
                  if (entry.$1 > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ServiceFeature(
                      repo: repo,
                      service: entry.$2,
                      poster: true,
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 12),
          SectionTitle(
            '陪练推荐',
            action: '全部',
            onTap: () => context.push('/players'),
          ),
          if (players.isEmpty)
            const Text('暂无陪练', style: TextStyle(color: muted))
          else
            ...players.take(3).map((p) => RosterRow(repo: repo, player: p)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('俱乐部公告'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/announcements'),
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2.05,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
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
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xC910151B)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 20,
                      bottom: 25,
                      child: Text(
                        '${banner['title']}',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (widget.repo.banners.length > 1)
            Positioned(
              left: 18,
              bottom: 8,
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
                    width: i == page ? 17 : 5,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: i == page ? 1 : .45,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.repo.banners.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Tooltip(
                message: '下一张横幅',
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0x66000000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(
                        color: Color(0x40FFFFFF),
                        width: .7,
                      ),
                    ),
                  ),
                  onPressed: () {
                    final next = (page + 1) % widget.repo.banners.length;
                    if (MediaQuery.of(context).reduceMotion ||
                        MediaQuery.of(context).disableAnimations) {
                      controller.jumpToPage(next);
                    } else {
                      controller.animateToPage(
                        next,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  child: Text(
                    '${page + 1} / ${widget.repo.banners.length}',
                    semanticsLabel:
                        '下一张横幅，当前第 ${page + 1} 张，共 ${widget.repo.banners.length} 张',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

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
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: selected ? rule : Colors.transparent,
                width: 1,
              ),
            ),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ServiceArt(service, radius: 12, icon: true),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${service['game']}',
            style: TextStyle(
              fontSize: 14,
              color: selected ? ink : muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );
}

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
    final title = Text(
      poster
          ? '${quote['platform'] == 'mobile' ? '手游' : quote['platform'] ?? ''} ${serviceKind(quote)}'
                .trim()
          : '${service['title']}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
    );
    final price = RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: ink),
        children: [
          TextSpan(
            text: '¥${money(quote)}',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: requestedVariant == null && variants.length > 1
                ? ' 起'
                : '/${priceUnit(quote)}',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
    return InkWell(
      onTap: () => context.push(
        Uri(
          path: '/services/${service['id']}',
          queryParameters: {'player': ?playerId, 'variant': ?variantId},
        ).toString(),
      ),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: embedded
            ? null
            : BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white, width: .7),
                boxShadow: [
                  BoxShadow(
                    color: ink.withValues(alpha: .035),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
        padding: poster ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: poster
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1.4,
                    child: ServiceArt(service, radius: 20),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            price,
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${quote['durationMinutes']}分钟',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 90,
                    height: 102,
                    child: ServiceArt(service, radius: 11),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 6),
                        Text(
                          '${quote['durationMinutes']} 分钟 · ${serviceKind(quote)}',
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                        const SizedBox(height: 9),
                        price,
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
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
    final fallback = ColoredBox(
      color: sage,
      child: Center(
        child: Text(
          game.isEmpty ? '游戏服务' : game,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: icon ? 11 : 16, color: muted),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.startsWith('https://')
          ? Image.network(
              url,
              fit: icon ? BoxFit.contain : BoxFit.cover,
              filterQuality: FilterQuality.high,
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
    );
  }
}

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
    return InkWell(
      onTap: () => context.push('/players/${player['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlayerArt(
              repo: repo,
              player: player,
              width: 88,
              height: 104,
              radius: 16,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${player['name']}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: muted,
                        size: 20,
                      ),
                    ],
                  ),
                  Text(
                    '${player['role']}',
                    style: const TextStyle(fontSize: 15, color: muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    (player['tags'] as List? ?? []).take(2).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (prices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '¥${money(prices.first)} 起',
                        style: TextStyle(
                          fontSize: 17,
                          color: brandColor(repo),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 12),
                  _DirectoryGames(
                    games: repo.services
                        .map((s) => '${s['game']}')
                        .toSet()
                        .toList(),
                    selected: game,
                    onSelected: (v) => setState(() => game = v),
                  ),
                  const SizedBox(height: 18),
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
                  ...items.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ServiceFeature(repo: repo, service: s),
                    ),
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
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: rule),
          const SizedBox(width: 12),
        ],
        for (final v in ['全部', ...games.where((v) => v.trim().isNotEmpty)])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected == v,
              label: Text(
                v == '全部' ? '全部游戏' : v,
                style: const TextStyle(fontSize: 14),
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
            const SizedBox(height: 18),
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
          const SizedBox(height: 12),
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
                size: 17,
                color: following ? onBrand(repo) : muted,
              ),
              label: const Text('本机关注', style: TextStyle(fontSize: 14)),
              onSelected: (v) => setState(() => following = v),
            ),
          ),
          const SizedBox(height: 12),
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
          ...items.map((p) => RosterRow(repo: repo, player: p)),
        ],
      );
    },
  );
}

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
    final players = repo.players
        .where((p) => (p['games'] as List).contains(s['game']))
        .toList();
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
                RichText(
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: ink),
                    children: [
                      TextSpan(
                        text: '¥${money(s)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '/${priceUnit(s)}',
                        style: const TextStyle(fontSize: 14, color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${s['durationMinutes']} 分钟',
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
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
          SizedBox(height: 192, child: ServiceArt(service, radius: 16)),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${s['title']}',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 44,
                height: 44,
                child: ServiceArt(service, radius: 10, icon: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${s['game']} · ${serviceKind(s)}',
            style: const TextStyle(fontSize: 14, color: muted),
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: 19),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: variants
                  .map(
                    (v) => ChoiceChip(
                      label: Text(
                        '${v['title']}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      selected: variantId == v['id'],
                      onSelected: (_) => setState(() => variantId = v['id']),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (serviceFacts(s).isNotEmpty) ...[
            const SizedBox(height: 15),
            Text(
              serviceFacts(s).join('   ·   '),
              style: const TextStyle(fontSize: 16),
            ),
          ],
          if ((s['maps'] as List? ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '地图  ${(s['maps'] as List).join(' / ')}',
                style: const TextStyle(fontSize: 16, color: muted),
              ),
            ),
          if ('${s['description'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '${s['description']}',
                style: const TextStyle(fontSize: 16, color: muted, height: 1.6),
              ),
            ),
          if (inclusions.isNotEmpty) ...[
            const Divider(),
            const Text(
              '服务内容',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...inclusions.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 21,
                      color: brandColor(repo),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('$v', style: const TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SectionTitle('可选陪练'),
          if (players.isEmpty)
            const Text('暂无陪练', style: TextStyle(color: muted))
          else
            ...players
                .take(2)
                .map(
                  (p) => MemberRow(
                    repo: repo,
                    player: p,
                    serviceId: '${service['id']}',
                    variantId: variantId,
                  ),
                ),
          if (rules.isNotEmpty || requirements.isNotEmpty) ...[
            const Divider(),
            const Text(
              '下单须知',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...[...rules, ...requirements].map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '$v',
                  style: const TextStyle(fontSize: 16, color: muted),
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          PlayerArt(
            repo: repo,
            player: player,
            width: 56,
            height: 64,
            radius: 12,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player['name']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${player['role']}',
                  style: const TextStyle(fontSize: 15, color: muted),
                ),
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded, size: 22, color: muted),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text(
              '选择游戏服务',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            for (final service in services)
              for (final variant
                  in serviceVariants(service).isEmpty
                      ? [service]
                      : serviceVariants(service))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    enabled:
                        (variant['teamSize'] as num? ??
                            service['teamSize'] as num? ??
                            1) <=
                        1,
                    title: Text(
                      '${service['title']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${variant['id'] == service['id'] ? '${variant['durationMinutes']}分钟' : variant['title']} · ¥${money(variant)} / ${priceUnit({...service, ...variant})}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, <String, dynamic>{
                      'service': '${service['id']}',
                      if (variant['id'] != service['id'])
                        'variant': '${variant['id']}',
                    }),
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
    return ClubPage(
      repo: repo,
      title: '陪练主页',
      actions: [
        IconButton(
          tooltip: repo.following.contains(widget.id) ? '取消关注' : '关注陪练',
          onPressed: () => repo.toggleFollow(widget.id),
          icon: Icon(
            repo.following.contains(widget.id)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 21,
          ),
        ),
      ],
      bottom: Row(
        children: [
          if (selectedPrice != null)
            Expanded(
              child: RichText(
                textScaler: MediaQuery.textScalerOf(context),
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: ink),
                  children: [
                    TextSpan(
                      text: '¥${money(selectedPrice)}',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: quote == null ? ' 起' : '/${priceUnit(quote)}',
                      style: const TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
            ),
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
            height: 245,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (services.isNotEmpty)
                  ServiceArt(contextService ?? services.first, radius: 18),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x1110171D), Color(0xF2161C24)],
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 26,
                  child: PlayerArt(
                    repo: repo,
                    player: p,
                    width: 127,
                    height: 170,
                    radius: 14,
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 160,
                  bottom: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${p['role']}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFD8DCE1),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        (p['games'] as List).join(' / '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFD8DCE1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (p['tags'] as List? ?? [])
                .map((v) => Tag('$v', fill: Colors.white, color: ink))
                .toList(),
          ),
          const SizedBox(height: 15),
          Text(
            '${p['bio']}',
            style: const TextStyle(fontSize: 16, height: 1.65, color: muted),
          ),
          const SizedBox(height: 10),
          if (quote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已选 ${quote['title']} · ${quote['variantTitle'] ?? '${quote['durationMinutes']}分钟'}',
                style: const TextStyle(fontSize: 14, color: muted),
              ),
            ),
          if (widget.serviceId != null && quote == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '原服务或规格已不可用，请重新选择。',
                style: TextStyle(fontSize: 14, color: muted),
              ),
            ),
          SectionTitle('服务'),
          if (services.isEmpty)
            const Text('暂无服务', style: TextStyle(color: muted)),
          ...services.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ServiceFeature(
                repo: repo,
                service: s,
                playerId: widget.id,
                variantId: quote != null && s['id'] == quote['id']
                    ? quote['variantId'] as String?
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SectionTitle(
            '明日可约时段',
            caption: '按 ${quote?['durationMinutes'] ?? 60} 分钟查看',
          ),
          if (failure != null)
            TextButton(onPressed: loadSlots, child: const Text('排班加载失败，重试'))
          else if (slots == null)
            const ClubSkeleton(kind: SkeletonKind.slots)
          else if (available!.isEmpty)
            const Text('暂无时段', style: TextStyle(fontSize: 16, color: muted))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: available
                  .take(4)
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        when(s['startAt'], onlyTime: true),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
