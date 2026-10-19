import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Decorative visitors live outside the scroll view and never receive input.
class EdgePetVisitors extends StatefulWidget {
  const EdgePetVisitors({super.key});
  @override
  State<EdgePetVisitors> createState() => _EdgePetVisitorsState();
}

class _EdgePetVisitorsState extends State<EdgePetVisitors>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  );
  bool _resumed = true;
  bool _reduceMotion = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _updateClock();
  }

  void _updateClock() {
    if (_reduceMotion || !_resumed) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updateClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  double entrance(double time) {
    if (time < 0 || time >= 4.5) return 0;
    if (time < .65) return Curves.easeOutCubic.transform(time / .65);
    if (time > 3.8) return 1 - Curves.easeInCubic.transform((time - 3.8) / .7);
    return 1;
  }

  Widget sprite(int index, double size) {
    // Individual bounds include transparent padding, avoiding adjacent sprites.
    const regions = [
      Rect.fromLTRB(40, 18, 468, 530),
      Rect.fromLTRB(475, 18, 850, 530),
      Rect.fromLTRB(934, 18, 1336, 530),
      Rect.fromLTRB(1338, 18, 1720, 530),
      Rect.fromLTRB(75, 558, 390, 860),
      Rect.fromLTRB(550, 558, 835, 860),
      Rect.fromLTRB(950, 558, 1258, 860),
      Rect.fromLTRB(1425, 558, 1700, 860),
    ];
    final rect = regions[index];
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: rect.width,
          height: rect.height,
          child: ClipPath(
            clipper: _AtlasRegionClipper(index),
            child: Stack(
              children: [
                Positioned(
                  left: -rect.left,
                  top: -rect.top,
                  width: 1792,
                  height: 896,
                  child: Image.asset(
                    'assets/images/edge_pet_variants.png',
                    fit: BoxFit.fill,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget visitor(int variant, double time) {
    final cat = variant.isOdd;
    final action = ((time - .8) / 2.4).clamp(0.0, 1.0);
    final wave = math.sin(action * math.pi * 6);
    final tap = math.pow(math.max(0.0, wave), 4).toDouble();
    return SizedBox(
      key: ValueKey('edgeVariant-$variant'),
      width: 120,
      height: 145,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Head and upper gripping paw stay completely still while greeting.
          Positioned(left: 0, top: 0, child: sprite(variant, 120)),
          Positioned(
            left: cat ? null : -4,
            right: cat ? 9 : null,
            top: cat ? 82 : 78,
            child: Transform.translate(
              key: const ValueKey('movingPetPaw'),
              offset: Offset(cat ? -tap * 4 : 0, cat ? tap * 2 : 0),
              child: Transform.rotate(
                angle: cat ? 0 : wave * .16,
                alignment: cat ? Alignment.bottomRight : Alignment.bottomLeft,
                child: Transform.scale(
                  scale: cat ? 1 + tap * .13 : 1,
                  alignment: cat ? Alignment.bottomRight : Alignment.bottomLeft,
                  child: sprite(variant + 4, cat ? 66 : 64),
                ),
              ),
            ),
          ),
          if (cat && tap > .15)
            Positioned(
              left: 30,
              top: 90,
              child: Opacity(
                opacity: tap * .5,
                child: Container(
                  width: 24 + tap * 10,
                  height: 24 + tap * 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final seconds = _clock.value * 120;
            final variant = (seconds / 30).floor().clamp(0, 3);
            final time = seconds - variant * 30 - 2;
            final reveal = entrance(time);
            final cat = variant.isOdd;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (reveal > 0)
                  Positioned(
                    key: ValueKey(cat ? 'edgeCat' : 'edgeDog'),
                    left: cat ? null : -23 - (1 - reveal) * 135,
                    // Keep the straight sprite edge and gripping surface offscreen.
                    right: cat ? -32 - (1 - reveal) * 135 : null,
                    top: cat
                        ? null
                        : MediaQuery.viewPaddingOf(context).top + 112,
                    bottom: cat
                        ? MediaQuery.viewPaddingOf(context).bottom + 104
                        : null,
                    child: visitor(variant, time),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Excludes neighbouring dog-ear fragments from both cat atlas cells.
class _AtlasRegionClipper extends CustomClipper<Path> {
  const _AtlasRegionClipper(this.index);
  final int index;

  @override
  Path getClip(Size size) {
    if (index != 1 && index != 3) return Path()..addRect(Offset.zero & size);
    final inset = index == 1 ? 30.0 : 38.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(inset, size.height)
      ..lineTo(inset, 332)
      ..lineTo(0, 332)
      ..close();
  }

  @override
  bool shouldReclip(_AtlasRegionClipper oldClipper) =>
      oldClipper.index != index;
}
