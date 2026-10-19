import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../../../../core/widgets/momiq_logo.dart';
import '../../../../core/localization/app_language.dart';
import '../../../../core/widgets/pressable_button.dart';
import '../../../../core/theme/brand_typography.dart';
import '../../../auth/presentation/pages/phone_page.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';

enum UserRole { customer, sitter }

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});
  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage>
    with TickerProviderStateMixin {
  UserRole _selected = UserRole.customer;
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  TextStyle _text(double size) => TextStyle(
    fontFamily: 'Quicksand',
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: AppColors.chocolate,
  );

  void _continue() {
    if (_selected == UserRole.customer) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const PhonePage(customer: true),
        ),
      );
      return;
    }
    if (_selected == UserRole.sitter) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const PhonePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return MomiqScaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: screen.width * .30,
            height: screen.height * .15,
            child: SvgPicture.asset(
              'assets/svg/decoration_top.svg',
              fit: BoxFit.fill,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            width: screen.width * .34,
            height: screen.height * .15,
            child: SvgPicture.asset(
              'assets/svg/decoration_bottom.svg',
              fit: BoxFit.fill,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Center(
                    child: SizedBox(
                      width: math.min(constraints.maxWidth, 480),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7EDE2),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(0xFFC9A17A),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: ['uz', 'en', 'ru'].map((
                                          language,
                                        ) {
                                          final selected =
                                              AppLanguage.current.value ==
                                              language;
                                          return Semantics(
                                            selected: selected,
                                            button: true,
                                            child: TextButton(
                                              key: ValueKey(
                                                'language-$language',
                                              ),
                                              onPressed: () {
                                                AppLanguage.select(language);
                                                setState(() {});
                                              },
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(44, 40),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                backgroundColor: selected
                                                    ? AppColors.gold
                                                    : Colors.transparent,
                                                foregroundColor:
                                                    AppColors.chocolate,
                                                shape: const StadiumBorder(),
                                              ),
                                              child: Text(
                                                language.toUpperCase(),
                                                style: _text(13),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  MomiqLogo(size: 26),
                                  Text('Momiq', style: momiqWordmark(25)),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      context.tr('Rolingizni tanlang'),
                                      textAlign: TextAlign.center,
                                      style: _text(28),
                                    ),
                                    const SizedBox(height: 36),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _card(
                                            UserRole.customer,
                                            context.tr('Mijozman'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _card(
                                            UserRole.sitter,
                                            context.tr('Enagaman'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                child: PressableButton(
                                  key: const ValueKey('continueButton'),
                                  onPressed: _continue,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.gold,
                                    foregroundColor: AppColors.chocolate,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    minimumSize: const Size.fromHeight(58),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 38),
                                      Expanded(
                                        child: Text(
                                          context.tr('Davom etish'),
                                          textAlign: TextAlign.center,
                                          style: _text(21),
                                        ),
                                      ),
                                      Container(
                                        width: 38,
                                        height: 38,
                                        padding: const EdgeInsets.all(9),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF8EEDF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const MomiqLogo(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(UserRole role, String label) {
    final selected = _selected == role;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7E3B0) : const Color(0xFFF7EDE2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            width: 1.6,
            color: selected ? AppColors.gold : const Color(0xFFC9A17A),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _selected = role),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? const Color(0xFFCE901B)
                              : Colors.transparent,
                          border: Border.all(
                            width: 1.5,
                            color: selected
                                ? const Color(0xFFCE901B)
                                : AppColors.brown,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.maxWidth;
                        return AnimatedBuilder(
                          animation: _motion,
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: ClipRect(
                              child: OverflowBox(
                                minWidth: size * 2,
                                maxWidth: size * 2,
                                minHeight: size,
                                maxHeight: size,
                                alignment: role == UserRole.customer
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: Image.asset(
                                  'assets/images/role_illustrations.png',
                                  width: size * 2,
                                  height: size,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              0,
                              -3 *
                                  math.sin(
                                    _motion.value * math.pi +
                                        (role == UserRole.sitter ? .6 : 0),
                                  ),
                            ),
                            child: child,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: _text(20), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
