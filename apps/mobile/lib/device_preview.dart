import 'package:flutter/widgets.dart';

/// 浏览器和截图的设备外观。真机使用系统状态栏，不叠加这层预览。
class IPhonePreview extends StatelessWidget {
  const IPhonePreview({super.key, required this.child});
  final Widget child;
  static const logicalSize = Size(390, 844);
  static const safeArea = EdgeInsets.only(top: 59, bottom: 34);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFE8EAEE),
    child: Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(46),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x280D1628),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(46),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: logicalSize,
                  padding: safeArea,
                  viewPadding: safeArea,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(child: _DeviceChrome()),
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
  );
}

class _DeviceChrome extends StatelessWidget {
  const _DeviceChrome();
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned(
        top: 16,
        left: 31,
        child: Text(
          '9:41',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            color: Color(0xFF101114),
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      ),
      Positioned(
        top: 11,
        left: 138,
        width: 114,
        height: 31,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF08090B),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      const Positioned(
        top: 20,
        right: 28,
        width: 66,
        height: 13,
        child: CustomPaint(painter: _StatusSymbols()),
      ),
      Positioned(
        bottom: 8,
        left: 128,
        width: 134,
        height: 5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF15171A),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(46),
            border: Border.all(color: const Color(0x8020242A), width: 1),
          ),
        ),
      ),
    ],
  );
}

class _StatusSymbols extends CustomPainter {
  const _StatusSymbols();
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFF15171A);
    for (var index = 0; index < 4; index++) {
      final height = 4.0 + index * 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(index * 4.3, 13 - height, 3, height),
          const Radius.circular(.7),
        ),
        fill,
      );
    }
    final stroke = Paint()
      ..color = const Color(0xFF15171A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(21, 1, 16, 16),
      3.92,
      1.57,
      false,
      stroke,
    );
    canvas.drawArc(
      const Rect.fromLTWH(24.5, 5, 9, 9),
      3.92,
      1.57,
      false,
      stroke,
    );
    canvas.drawCircle(const Offset(29, 11), 1.3, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 1, 21, 11),
        const Radius.circular(3),
      ),
      Paint()
        ..color = const Color(0x8015171A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 3, 17, 7),
        const Radius.circular(1.2),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(64.5, 4, 1.5, 5),
        const Radius.circular(1),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StatusSymbols oldDelegate) => false;
}
