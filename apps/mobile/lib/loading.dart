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

  Widget _line(double width, {double height = 13}) => Align(
    alignment: Alignment.centerLeft,
    child: SkeletonBlock(width: width, height: height, radius: 4),
  );

  Widget _row({double imageWidth = 44, double imageHeight = 50}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SkeletonBlock(width: imageWidth, height: imageHeight, radius: 11),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(132, height: 15),
              const SizedBox(height: 6),
              _line(176),
              const SizedBox(height: 6),
              _line(92, height: 10),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card({double imageHeight = 0}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageHeight > 0) ...[
          SkeletonBlock(height: imageHeight, radius: 10),
          const SizedBox(height: 10),
        ],
        _line(92, height: 15),
        const SizedBox(height: 7),
        const SkeletonBlock(height: 13, radius: 4),
        const SizedBox(height: 5),
        _line(176, height: 10),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(child: _line(112)),
            const SkeletonBlock(width: 42, height: 16, radius: 4),
          ],
        ),
      ],
    ),
  );

  Widget _homeSection() => const Padding(
    padding: EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        SkeletonBlock(width: 84, height: 17, radius: 4),
        Spacer(),
        SkeletonBlock(width: 34, height: 12, radius: 4),
      ],
    ),
  );


  Widget _slots() => const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      SkeletonBlock(width: 74, height: 46),
      SkeletonBlock(width: 74, height: 46),
      SkeletonBlock(width: 74, height: 46),
      SkeletonBlock(width: 74, height: 46),
      SkeletonBlock(width: 74, height: 46),
      SkeletonBlock(width: 74, height: 46),
    ],
  );

  List<Widget> _body() => switch (kind) {
    SkeletonKind.home => [
      Row(
        children: [
          const SkeletonBlock(width: 32, height: 32, radius: 9),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_line(110, height: 15), const SizedBox(height: 5), _line(160, height: 11)],
            ),
          ),
          const SkeletonBlock(width: 34, height: 34, radius: 17),
        ],
      ),
      const SizedBox(height: 12),
      const SkeletonBlock(height: 38, radius: 12),
      const SizedBox(height: 10),
      const SkeletonBlock(height: 104, radius: 16),
      const SizedBox(height: 12),
      const SkeletonBlock(height: 160, radius: 16),
      const SizedBox(height: 14),
      SizedBox(
        height: 88,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: double.infinity,
                        child: SkeletonBlock(height: 56, radius: 11),
                      ),
                      const SizedBox(height: 5),
                      FractionallySizedBox(
                        widthFactor: .66,
                        child: const SizedBox(
                          width: double.infinity,
                          child: SkeletonBlock(height: 10, radius: 4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      _homeSection(),
      _card(imageHeight: 120),
      const SizedBox(height: 8),
      _card(),
      _homeSection(),
      _row(),
    ],
    SkeletonKind.catalog => [
      const SkeletonBlock(height: 38, radius: 12),
      const SizedBox(height: 10),
      const SkeletonBlock(height: 38, radius: 11),
      const SizedBox(height: 8),
      const Row(
        children: [
          SkeletonBlock(width: 64, height: 30, radius: 15),
          SizedBox(width: 6),
          SkeletonBlock(width: 82, height: 30, radius: 15),
          SizedBox(width: 6),
          SkeletonBlock(width: 82, height: 30, radius: 15),
        ],
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < 4; i++) ...[_row(imageWidth: 92, imageHeight: 88), const SizedBox(height: 7)],
    ],
    SkeletonKind.order => [
      const SkeletonBlock(height: 148, radius: 17),
      const SizedBox(height: 12),
      Row(
        children: [
          for (var i = 0; i < 4; i++)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 6),
                child: SkeletonBlock(height: 14, radius: 4),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _card(),
      const SizedBox(height: 10),
      _row(imageWidth: 48, imageHeight: 52),
      _homeSection(),
      for (var i = 0; i < 3; i++) _row(imageWidth: 10, imageHeight: 10),
    ],
    SkeletonKind.member => [
      const SkeletonBlock(height: 182, radius: 19),
      const SizedBox(height: 10),
      Row(
        children: [
          for (var i = 0; i < 3; i++)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: SkeletonBlock(height: 38, radius: 12),
              ),
            ),
        ],
      ),
      _homeSection(),
      _card(imageHeight: 78),
      const SizedBox(height: 8),
      _card(),
    ],
    SkeletonKind.earnings => [
      const SkeletonBlock(height: 196, radius: 19),
      const SizedBox(height: 10),
      _line(256),
      _homeSection(),
      for (var i = 0; i < 3; i++) ...[
        _card(imageHeight: 0),
        const SizedBox(height: 8),
      ],
    ],
    SkeletonKind.profile => [
      const SkeletonBlock(height: 162, radius: 19),
      const SizedBox(height: 10),
      Row(
        children: const [
          Expanded(child: SkeletonBlock(height: 52, radius: 15)),
          SizedBox(width: 8),
          Expanded(child: SkeletonBlock(height: 52, radius: 15)),
        ],
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < 5; i++) _row(imageWidth: 24, imageHeight: 24),
    ],
    SkeletonKind.notifications => [
      for (var i = 0; i < 5; i++) ...[
        _row(imageWidth: 32, imageHeight: 34),
        const SizedBox(height: 5),
      ],
    ],
    SkeletonKind.availability => [
      const SkeletonBlock(width: 110, height: 22, radius: 4),
      const SizedBox(height: 8),
      _line(220),
      const SizedBox(height: 14),
      for (var i = 0; i < 4; i++) ...[
        _row(imageWidth: 36, imageHeight: 40),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 8),
      const SkeletonBlock(height: 42, radius: 13),
    ],
    SkeletonKind.slots => [],
  };

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: kind == SkeletonKind.slots
        ? _slots()
        : PageList(
            padding: kind == SkeletonKind.home
                ? const EdgeInsets.fromLTRB(16, 8, 16, 22)
                : const EdgeInsets.fromLTRB(16, 6, 16, 26),
            children: _body(),
          ),
  );
}
