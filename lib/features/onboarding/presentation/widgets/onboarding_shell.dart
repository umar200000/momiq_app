import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../../../../core/widgets/momiq_logo.dart';
import '../../../../core/localization/app_language.dart';
import '../../../../core/widgets/pressable_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/brand_typography.dart';

const formSurface = Color(0xFFF7EDE2);
const formBorder = Color(0xFFC8AF91);
TextStyle profileText(double size, {bool bold = false}) => TextStyle(
  fontFamily: 'Quicksand',
  fontSize: size,
  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  color: AppColors.chocolate,
);

class OnboardingShell extends StatelessWidget {
  const OnboardingShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MomiqScaffold(
    resizeToAvoidBottomInset: false,
    backgroundColor: AppColors.cream,
    body: GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: 95,
            height: 135,
            child: SvgPicture.asset(
              'assets/svg/decoration_top.svg',
              fit: BoxFit.fill,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            width: 120,
            height: 110,
            child: SvgPicture.asset(
              'assets/svg/decoration_bottom.svg',
              fit: BoxFit.fill,
            ),
          ),
          SafeArea(
            maintainBottomViewPadding: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: context.tr('Orqaga'),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.chocolate,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Momiq', style: momiqWordmark(27)),
                            const SizedBox(width: 6),
                            MomiqLogo(size: 25),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: child,
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

class ProfileButton extends StatelessWidget {
  const ProfileButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: PressableButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.chocolate,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: profileText(17, bold: true),
      ),
    ),
  );
}
