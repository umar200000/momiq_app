import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/theme/app_colors.dart';

class SleepingPuppy extends StatefulWidget {
  const SleepingPuppy({super.key});
  @override
  State<SleepingPuppy> createState() => _SleepingPuppyState();
}

class _SleepingPuppyState extends State<SleepingPuppy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sleep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sleep.stop();
    } else if (!_sleep.isAnimating) {
      _sleep.repeat();
    }
  }

  @override
  void dispose() {
    _sleep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 112,
      height: 94,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            child: SvgPicture.asset('assets/svg/puppy.svg', width: 105),
          ),
          AnimatedBuilder(
            animation: _sleep,
            builder: (context, _) => Stack(
              children: List.generate(3, (index) {
                final t = (_sleep.value + index / 3) % 1;
                return Positioned(
                  left: 24 + t * 25,
                  top: 34 - t * 32,
                  child: Opacity(
                    opacity: math.sin(t * math.pi).clamp(0.0, 1.0),
                    child: Text(
                      'z',
                      style: TextStyle(
                        fontFamily: 'Quicksand',
                        fontWeight: FontWeight.w600,
                        fontSize: 12 + t * 6,
                        color: AppColors.brown,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    ),
  );
}
