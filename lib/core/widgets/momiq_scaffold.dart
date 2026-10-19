import 'edge_pet_visitors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';

/// One shared background for both roles, always underneath interactive content.
class MomiqPawBackdrop extends StatelessWidget {
  const MomiqPawBackdrop({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, bounds) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final p in const [
              (.78, .02, 110.0, .4),
              (.08, .08, 45.0, -.35),
              (-.04, .23, 75.0, -.45),
              (.83, .34, 62.0, .3),
              (.38, .43, 48.0, -.3),
              (.76, .57, 130.0, -.3),
              (-.03, .64, 78.0, .35),
              (.40, .78, 44.0, -.4),
              (.04, .86, 52.0, .4),
              (.85, .92, 68.0, -.35),
            ])
              Positioned(
                left: bounds.maxWidth * p.$1,
                top: bounds.maxHeight * p.$2,
                child: Transform.rotate(
                  angle: p.$4,
                  child: Opacity(
                    opacity: .095,
                    child: SvgPicture.asset(
                      'assets/svg/paw.svg',
                      width: p.$3,
                      colorFilter: const ColorFilter.mode(
                        AppColors.brown,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class MomiqScaffold extends StatelessWidget {
  const MomiqScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.resizeToAvoidBottomInset,
    this.showPetVisitors = false,
  });
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool? resizeToAvoidBottomInset;
  final bool showPetVisitors;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor,
        bottomNavigationBar: bottomNavigationBar,
        extendBody: extendBody,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(child: MomiqPawBackdrop()),
            ),
            body,
          ],
        ),
      ),
      // Keep one full-screen visitor layer above the scaffold and its navigation.
      // Loading, refresh, tabs and app bars must not reset or clip the pet cycle.
      if (showPetVisitors)
        const Positioned.fill(
          key: ValueKey('petVisitorsOverlay'),
          child: EdgePetVisitors(),
        ),
    ],
  );
}
