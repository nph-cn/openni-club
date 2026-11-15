import 'package:material_ui/material_ui.dart';

import 'ui.dart' show canvas, ink, PageList;

enum SkeletonKind {
  home,
  catalog,
  order,
  member,
  earnings,
  profile,
  slots,
  notifications,
  availability,
}

/// A decorative placeholder. Animation belongs to its shared [SkeletonPulse].
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          ink.withValues(
            alpha: MediaQuery.maybeOf(context)?.highContrast == true ? .2 : .08,
          ),
          canvas,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// One quiet pulse for the whole loading region, with a single announcement.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1,
    );
    _opacity = Tween<double>(
      begin: .72,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final shouldAnimate =
        TickerMode.valuesOf(context).enabled &&
        !(media?.disableAnimations ?? false) &&
        !(media?.reduceMotion ?? false) &&
        !(media?.highContrast ?? false);
    if (shouldAnimate == _animating) return;
    _animating = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '正在加载',
    child: ExcludeSemantics(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    ),
  );
}

/// Keeps the page's real content geometry visible while its first read resolves.
class ClubSkeleton extends StatelessWidget {
  const ClubSkeleton({super.key, required this.kind});

  final SkeletonKind kind;

  static const _gap = SizedBox(height: 16);
  static const _smallGap = SizedBox(height: 8);

  Widget _line(double width, {double height = 14}) => Align(
    alignment: Alignment.centerLeft,
    child: SkeletonBlock(width: width, height: height, radius: 5),
  );

  Widget _row({double imageWidth = 48, double imageHeight = 54}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SkeletonBlock(width: imageWidth, height: imageHeight),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(132, height: 18),
              _smallGap,
              _line(176),
              _smallGap,
              _line(92, height: 12),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(92, height: 20),
        _gap,
        const SkeletonBlock(height: 18, radius: 5),
        _smallGap,
        _line(176, height: 12),
        _gap,
        Row(
          children: [
            Expanded(child: _line(112)),
            const SkeletonBlock(width: 42, height: 20, radius: 5),
          ],
        ),
      ],
    ),
  );

  Widget _homePoster() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AspectRatio(
          aspectRatio: 1.95,
          child: SkeletonBlock(height: 86, radius: 14),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(100, height: 20),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _line(64, height: 28)),
                  const SkeletonBlock(width: 40, height: 11, radius: 4),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _homeSection() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 10),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          _line(96, height: 22),
          const Spacer(),
          const SkeletonBlock(width: 42, height: 14, radius: 5),
        ],
      ),
    ),
  );

  Widget _metrics({double height = 100}) => SkeletonBlock(height: height);

  Widget _slots() => const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      SkeletonBlock(width: 102, height: 48),
      SkeletonBlock(width: 102, height: 48),
      SkeletonBlock(width: 102, height: 48),
      SkeletonBlock(width: 102, height: 48),
      SkeletonBlock(width: 102, height: 48),
      SkeletonBlock(width: 102, height: 48),
    ],
  );

  List<Widget> _body() => switch (kind) {
    SkeletonKind.home => [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            const SkeletonBlock(width: 30, height: 30, radius: 8),
            const SizedBox(width: 9),
            _line(120, height: 22),
            const Spacer(),
            const SizedBox(
              width: 48,
              child: Center(
                child: SkeletonBlock(width: 20, height: 20, radius: 6),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const SkeletonBlock(height: 44),
      _gap,
      const SkeletonBlock(height: 156, radius: 16),
      const SizedBox(height: 20),
      Row(
        children: [
          for (var i = 0; i < 3; i++)
            const Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Center(child: SkeletonBlock(width: 50, height: 50)),
                  ),
                  SizedBox(height: 6),
                  SkeletonBlock(width: 64, height: 20, radius: 5),
                ],
              ),
            ),
        ],
      ),
      _smallGap,
      _homeSection(),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _homePoster()),
          const SizedBox(width: 12),
          Expanded(child: _homePoster()),
        ],
      ),
      const SizedBox(height: 12),
      _homeSection(),
      _row(imageWidth: 88, imageHeight: 104),
    ],
    SkeletonKind.catalog => [
      const SkeletonBlock(height: 48),
      _gap,
      const Row(
        children: [
          SkeletonBlock(width: 64, height: 36, radius: 18),
          SizedBox(width: 8),
          SkeletonBlock(width: 92, height: 36, radius: 18),
          SizedBox(width: 8),
          SkeletonBlock(width: 92, height: 36, radius: 18),
        ],
      ),
      _gap,
      _card(),
      _gap,
      _card(),
      _gap,
      _card(),
    ],
    SkeletonKind.order => [
      _line(96, height: 28),
      _gap,
      _line(240, height: 30),
      _smallGap,
      _line(176),
      _gap,
      _card(),
      _gap,
      _row(imageWidth: 56, imageHeight: 64),
      _gap,
      _line(96, height: 22),
      _gap,
      for (var i = 0; i < 3; i++) _row(imageWidth: 12, imageHeight: 12),
    ],
    SkeletonKind.member => [
      _row(imageWidth: 56, imageHeight: 64),
      _gap,
      _metrics(height: 110),
      _gap,
      const SkeletonBlock(height: 52),
      _gap,
      _line(96, height: 22),
      _gap,
      _card(),
      _gap,
      _line(132, height: 22),
      _row(),
      _row(),
    ],
    SkeletonKind.earnings => [
      _metrics(height: 205),
      _gap,
      _line(256),
      _gap,
      _line(160, height: 22),
      _gap,
      for (var i = 0; i < 4; i++) ...[
        _line(180, height: 18),
        _smallGap,
        _line(126, height: 12),
        _gap,
        const Divider(height: 1),
        _gap,
      ],
    ],
    SkeletonKind.profile => [
      _gap,
      _row(imageWidth: 58, imageHeight: 58),
      _gap,
      _metrics(),
      _gap,
      for (var i = 0; i < 4; i++) _row(imageWidth: 24, imageHeight: 24),
    ],
    SkeletonKind.notifications => [
      for (var i = 0; i < 5; i++) ...[
        _row(imageWidth: 36, imageHeight: 36),
        _gap,
      ],
    ],
    SkeletonKind.availability => [
      _line(120, height: 23),
      _gap,
      _line(64),
      _gap,
      for (var i = 0; i < 3; i++) ...[
        _row(imageWidth: 24, imageHeight: 24),
        _smallGap,
      ],
      _gap,
      const SkeletonBlock(height: 48),
    ],
    SkeletonKind.slots => [],
  };

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: kind == SkeletonKind.slots
        ? _slots()
        : PageList(
            padding: kind == SkeletonKind.home
                ? const EdgeInsets.fromLTRB(20, 10, 20, 24)
                : const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: _body(),
          ),
  );
}
