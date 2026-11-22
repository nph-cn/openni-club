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
              BrandMark(repo, size: 30),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  repo.clubName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '通知',
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => context.go('/services'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, size: 21, color: muted),
                  SizedBox(width: 9),
                  Text(
                    '搜索游戏、服务、陪练',
                    style: TextStyle(fontSize: 15, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (repo.banners.isNotEmpty)
            HomeBanners(repo)
          else if (services.isNotEmpty)
            AspectRatio(
              aspectRatio: 2.25,
              child: ServiceArt(services.first, radius: 16, banner: true),
            ),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InkWell(
                onTap: () => context.push('/orders/${active['id']}'),
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
          if (repo.announcements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InkWell(
                onTap: () => context.push('/announcements'),
                child: Row(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 18,
                      color: brandColor(repo),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${repo.announcements.first['title']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${repo.announcements.first['body'] ?? ''}',
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
          const SizedBox(height: 20),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: games.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, i) {
                final game = games[i];
                return GameSelector(
                  service: repo.services.firstWhere((s) => s['game'] == game),
                  selected: selectedGame == game,
                  onTap: () => setState(() => selectedGame = game),
                );
              },
            ),
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
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2.25,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          PageView.builder(
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
                      bottom: 24,
                      child: Text(
                        '${banner['title']}',
                        style: const TextStyle(
                          fontSize: 23,
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
              bottom: 12,
              child: Row(
                children: List.generate(
                  widget.repo.banners.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
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
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? ink : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: SizedBox(
            width: 47,
            height: 47,
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
  );
}

class ServiceFeature extends StatelessWidget {
  const ServiceFeature({
    super.key,
    required this.repo,
    required this.service,
    this.embedded = false,
    this.poster = false,
    this.onTap,
  });
  final ClubRepository repo;
  final Json service;
  final bool embedded, poster;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final variants = serviceVariants(service);
    final lowest = variants.isEmpty
        ? service
        : variants.reduce((a, b) => a['priceCents'] < b['priceCents'] ? a : b);
    final quote = {...service, ...lowest};
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
      text: TextSpan(
        style: const TextStyle(fontFamily: 'NotoSansSC', color: ink),
        children: [
          TextSpan(
            text: '¥${money(quote)}',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          TextSpan(
            text: variants.length > 1 ? ' 起' : '/${priceUnit(quote)}',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
    return InkWell(
      onTap: onTap ?? () => context.push('/services/${service['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: embedded
            ? null
            : BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
        padding: poster ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: poster
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1.95,
                    child: ServiceArt(service, radius: 14),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        if ('${quote['description'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${quote['description']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            price,
                            const Spacer(),
                            Text(
                              '${quote['durationMinutes']}分钟',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
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
                        if ('${quote['description'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${quote['description']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: muted,
                              height: 1.4,
                            ),
                          ),
                        ],
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
              fit: BoxFit.cover,
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
                      if (player['status'] == 'available') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9F3EC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '可约',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D4F),
                            ),
                          ),
                        ),
                      ],
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
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final items = repo.services
        .where(
          (s) =>
              (game == '全部' || s['game'] == game) &&
              '${s['title']} ${s['game']} ${s['description']}'.contains(query),
        )
        .toList();
    return ClubPage(
      repo: repo,
      title: '找服务',
      tab: 1,
      child: PageList(
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '搜索游戏或服务',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['全部', ...repo.services.map((s) => '${s['game']}').toSet()]
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: game == v,
                            label: Text(
                              v,
                              style: const TextStyle(fontSize: 15),
                            ),
                            onSelected: (_) => setState(() => game = v),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (items.isEmpty) const EmptyState('没有匹配的服务', '试试其他游戏或关键词。'),
          ...items.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ServiceFeature(repo: repo, service: s),
            ),
          ),
        ],
      ),
    );
  }
}

class ServicePage extends StatefulWidget {
  const ServicePage(this.repo, this.id, {super.key, this.initialVariant});
  final ClubRepository repo;
  final String id;
  final String? initialVariant;
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
          IconButton(
            tooltip: '联系俱乐部',
            onPressed: () => textSheet(
              context,
              '联系俱乐部',
              '${repo.club['supportContact'] ?? '请通过运营方公示渠道联系。'}',
            ),
            icon: const Icon(Icons.headset_mic_outlined, size: 23),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'NotoSansSC',
                      color: ink,
                    ),
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
                      '/book?service=${service['id']}${variantId == null ? '' : '&variant=$variantId'}',
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
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEFEF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '本平台提供陪练与组队协作，不提供上号代练、代打，双方各自使用本人游戏账号。',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF9A3A3A),
                height: 1.5,
              ),
            ),
          ),
          SectionTitle('可选陪练'),
          if (players.isEmpty)
            const Text('暂无陪练', style: TextStyle(color: muted))
          else
            ...players.take(2).map((p) => MemberRow(repo: repo, player: p)),
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
  });
  final ClubRepository repo;
  final Json player;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/players/${player['id']}'),
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

class PlayersPage extends StatefulWidget {
  const PlayersPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  String query = '';
  String game = '全部';
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final q = query.trim();
    final games = repo.players
        .expand((p) => (p['games'] as List? ?? []).map((g) => '$g'))
        .toSet()
        .toList();
    final players = repo.players
        .where(
          (p) =>
              (game == '全部' || (p['games'] as List? ?? []).contains(game)) &&
              (q.isEmpty ||
                  '${p['name']} ${p['role']} ${(p['games'] as List? ?? []).join(' ')}'
                      .contains(q)),
        )
        .toList();
    return ClubPage(
      repo: repo,
      title: '俱乐部陪练',
      child: PageList(
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '搜索成员或游戏',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['全部', ...games]
                  .map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: game == v,
                        label: Text(v, style: const TextStyle(fontSize: 15)),
                        onSelected: (_) => setState(() => game = v),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (players.isEmpty)
            const Text('没有匹配的成员', style: TextStyle(color: muted)),
          ...players.map((p) => RosterRow(repo: repo, player: p)),
        ],
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage(this.repo, this.id, {super.key});
  final ClubRepository repo;
  final String id;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  List<Json>? slots;
  String? failure;
  @override
  void initState() {
    super.initState();
    loadSlots();
  }

  Future<void> loadSlots() async {
    setState(() {
      failure = null;
      slots = null;
    });
    try {
      final today = widget.repo.now.toUtc().add(const Duration(hours: 8));
      final value = await widget.repo.getAvailability(
        widget.id,
        DateTime(today.year, today.month, today.day + 1),
        60,
      );
      if (mounted) {
        setState(() {
          slots = value;
          failure = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  Future<void> chooseService(List<Json> services, String playerId) async {
    final serviceId = await showClubSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择预约服务',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: services.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final service = services[index];
                      return ServiceFeature(
                        repo: widget.repo,
                        service: service,
                        onTap: () => Navigator.pop(ctx, '${service['id']}'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (serviceId != null && mounted) {
      context.push(
        Uri(
          path: '/book',
          queryParameters: {'service': serviceId, 'player': playerId},
        ).toString(),
      );
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
          if (prices.isNotEmpty)
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'NotoSansSC', color: ink),
                  children: [
                    TextSpan(
                      text: '¥${money(prices.first)}',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const TextSpan(
                      text: ' 起',
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: FilledButton(
              onPressed: services.isEmpty
                  ? null
                  : () => chooseService(services, '${p['id']}'),
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
                if (services.isNotEmpty) ServiceArt(services.first, radius: 18),
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
          SectionTitle('服务'),
          if (services.isEmpty)
            const Text('暂无服务', style: TextStyle(color: muted)),
          ...services.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ServiceFeature(repo: repo, service: s),
            ),
          ),
          const SizedBox(height: 5),
          SectionTitle('明日可约时段'),
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
