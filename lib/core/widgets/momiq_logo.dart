import 'package:flutter/material.dart';

/// The approved heart-paw brand mark, shared by every branded screen.
class MomiqLogo extends StatelessWidget {
  const MomiqLogo({super.key, this.size = 30});
  final double size;
  static const asset = 'assets/images/momiq_heart_logo.png';

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Transform.scale(
        scale: 1.10,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}
