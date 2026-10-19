import 'package:flutter/material.dart';

/// Reusable skeleton; reduced-motion users receive the same static structure.
class MomiqShimmer extends StatefulWidget {
  const MomiqShimmer({super.key, required this.child});
  final Widget child;
  @override
  State<MomiqShimmer> createState() => _MomiqShimmerState();
}

class _MomiqShimmerState extends State<MomiqShimmer>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-3 + 6 * _animation.value, 0),
            end: Alignment(-1 + 6 * _animation.value, 0),
            colors: const [
              Color(0xFFE3D7C7),
              Color(0xFFF8F1E7),
              Color(0xFFE3D7C7),
            ],
            stops: const [0, .5, 1],
          ).createShader(bounds),
          child: child,
        ),
      ),
    ),
  );
}

class CustomerHomeSkeleton extends StatelessWidget {
  const CustomerHomeSkeleton({super.key});
  Widget box(double height, {double? width, double radius = 16}) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      color: const Color(0xFFE3D7C7),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Ma’lumotlar yuklanmoqda',
    liveRegion: true,
    child: MomiqShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(28, width: 210),
          const SizedBox(height: 12),
          box(16, width: 115),
          const SizedBox(height: 24),
          box(54),
          const SizedBox(height: 18),
          box(192, radius: 26),
          const SizedBox(height: 24),
          box(22, width: 190),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: box(150),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          box(22, width: 235),
          const SizedBox(height: 16),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: box(280, radius: 24),
            ),
        ],
      ),
    ),
  );
}
