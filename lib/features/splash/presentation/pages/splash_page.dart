import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../../../../core/widgets/momiq_logo.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/brand_typography.dart';
import '../../../../core/utils/responsive.dart';
import '../../../role_selection/presentation/pages/role_selection_page.dart';

/// Splash ekran — dizayndagi HTML/CSS maketning aynan o'zi.
///
/// O'lchamlar CSS `clamp()` va foizlaridan bir-biriga mos ko'chirilgan,
/// shakllar esa asl SVG `path`lari (`assets/svg/`).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            transitionDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 450),
            pageBuilder: (context, animation, secondaryAnimation) =>
                const RoleSelectionPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // SVG viewBox nisbatlari — CSS'dagi `height: auto` ni takrorlash uchun.

  static const double _puppyRatio = 110 / 180;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final double w = screen.width;
    final double h = screen.height;
    final double safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // .paw  -> width: clamp(125px, 38vw, 165px)
    final double pawWidth = cssClamp(125, w * 0.38, 165);
    // h1    -> font-size: clamp(64px, 14vw, 82px)
    final double titleSize = cssClamp(64, w * 0.14, 82);
    // .subtitle -> font-size: clamp(18px, 4.8vw, 22px)
    final double subtitleSize = cssClamp(18, w * 0.048, 22);
    // .puppy -> width: clamp(90px, 26vw, 116px)
    final double puppyWidth = cssClamp(90, w * 0.26, 116);
    // .puppy -> bottom: max(8.5%, env(safe-area-inset-bottom))
    final double puppyBottom = math.max(h * 0.085, safeBottom);
    // .brand -> width: min(90%, 410px)
    final double brandWidth = math.min(w * 0.9, 410);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.cream,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MomiqScaffold(
        backgroundColor: AppColors.cream,
        body: Stack(
          children: [
            // .decoration--top -> top: 0; right: 0; width: 49%; height: 29%
            Positioned(
              top: 0,
              right: 0,
              width: w * 0.49,
              height: h * 0.29,
              child: SvgPicture.asset(
                'assets/svg/decoration_top.svg',
                fit: BoxFit.fill, // preserveAspectRatio="none"
              ),
            ),

            // .decoration--bottom -> bottom: 0; left: 0; width: 34%; height: 15%
            Positioned(
              bottom: 0,
              left: 0,
              width: w * 0.34,
              height: h * 0.15,
              child: SvgPicture.asset(
                'assets/svg/decoration_bottom.svg',
                fit: BoxFit.fill,
              ),
            ),

            // .brand -> top/left 50% + translate(-50%, -50%)
            Center(
              child: SizedBox(
                width: brandWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MomiqLogo(size: pawWidth),
                    const SizedBox(height: 16), // .paw margin-bottom
                    Text(
                      'Momiq',
                      textAlign: TextAlign.center,
                      style: momiqWordmark(titleSize),
                    ),
                    const SizedBox(height: 17), // .subtitle margin-top
                    Text(
                      "Do'stingiz\nishonchli qo'llarda.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Quicksand',
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brown,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // .puppy -> bottom + left 50% + translateX(-50%)
            Positioned(
              left: 0,
              right: 0,
              bottom: puppyBottom,
              child: Center(
                child: _SleepingPuppy(
                  width: puppyWidth,
                  height: puppyWidth * _puppyRatio,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animates only the sleep letters, leaving the rest of the splash still.
class _SleepingPuppy extends StatefulWidget {
  const _SleepingPuppy({required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<_SleepingPuppy> createState() => _SleepingPuppyState();
}

class _SleepingPuppyState extends State<_SleepingPuppy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.45;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = widget.width * 0.48;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            width: widget.width,
            height: widget.height + rise,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: SvgPicture.asset(
                    'assets/svg/puppy.svg',
                    width: widget.width,
                    height: widget.height,
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Stack(
                      children: List.generate(3, (index) {
                        final progress = (_controller.value + index / 3) % 1.0;
                        final opacity = math.sin(math.pi * progress) * 0.85;
                        return Positioned(
                          left: widget.width * (0.22 + progress * 0.22),
                          bottom: widget.height * 0.83 + rise * progress,
                          child: Opacity(
                            opacity: opacity,
                            child: Transform.rotate(
                              angle: -0.14 + progress * 0.22,
                              child: Text(
                                'Z',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontFamily: 'Quicksand',
                                  fontSize:
                                      widget.width * (0.11 + progress * 0.07),
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brown,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
