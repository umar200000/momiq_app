import 'package:momiq_app/core/widgets/button_progress.dart';
import '../session_destination.dart';
import '../../../customer/data/customer_api.dart';
import '../../../../core/config/auth_features.dart';
import '../../../customer/presentation/customer_registration_page.dart';
import '../../../onboarding/presentation/pages/sitter_registration_page.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../../../../core/widgets/momiq_logo.dart';
import '../../../../core/localization/app_language.dart';
import '../../../../core/widgets/pressable_button.dart';
import '../../../onboarding/presentation/pages/myid_page.dart';
import '../../../../core/theme/brand_typography.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';

TextStyle authText(double size, {bool bold = false, Color? color}) => TextStyle(
  fontFamily: 'Quicksand',
  fontSize: size,
  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  color: color ?? AppColors.chocolate,
);

/// Local Uzbekistan number formatter. The country prefix is rendered separately.
class UzbekistanPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text;
    var cursor = newValue.selection.extentOffset.clamp(0, raw.length);
    // Backspacing a grouping space should delete the preceding digit as well.
    if (oldValue.text.length == raw.length + 1 &&
        cursor > 0 &&
        cursor < oldValue.text.length &&
        oldValue.text[cursor] == ' ' &&
        oldValue.selection.isCollapsed) {
      raw = raw.replaceRange(cursor - 1, cursor, '');
      cursor--;
    }
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    var before = raw.substring(0, cursor).replaceAll(RegExp(r'\D'), '').length;
    if (digits.length > 9 && digits.startsWith('998')) {
      digits = digits.substring(3);
      before = math.max(0, before - 3);
    }
    digits = digits.substring(0, math.min(9, digits.length));
    before = before.clamp(0, digits.length);
    final result = StringBuffer();
    var caret = 0;
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) result.write(' ');
      result.write(digits[i]);
      if (i < before) caret = result.length;
    }
    return TextEditingValue(
      text: result.toString(),
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}

class PhonePage extends StatefulWidget {
  const PhonePage({super.key, this.customer = false});
  final bool customer;
  @override
  State<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends State<PhonePage> {
  final _phone = TextEditingController();
  String? _error;
  bool _opening = false;
  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_opening) return;
    if (_phone.text.replaceAll(' ', '').length != 9) {
      setState(() => _error = '9 xonali telefon raqamini kiriting');
      return;
    }
    setState(() => _opening = true);
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OtpPage(phone: '+998 ${_phone.text}', customer: widget.customer),
      ),
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    puppy: false,
    title: context.tr('Telefon raqamingiz'),
    subtitle: context.tr('Boshlash uchun raqamingizni kiriting'),
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _error == null
                ? const Color(0xFFC8AF91)
                : Colors.red.shade700,
          ),
        ),
        child: Row(
          children: [
            Text('+998', style: authText(20, bold: true)),
            Container(
              height: 28,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: const Color(0xFFD5BFA5),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('phoneInput'),
                readOnly: _opening,
                controller: _phone,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [UzbekistanPhoneFormatter()],
                style: authText(20),
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: '00 000 00 00',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFFA59B90)),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _send(),
              ),
            ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            context.tr(_error!),
            style: authText(14, color: Colors.red.shade700),
          ),
        ),
      const SizedBox(height: 24),
      AuthButton(
        label: context.tr('Kod yuborish'),
        loading: _opening,
        onPressed: _send,
      ),
    ],
  );
}

class OtpPage extends StatefulWidget {
  const OtpPage({
    super.key,
    required this.phone,
    this.customer = false,
    this.authenticate,
  });
  final Future<Map<String, dynamic>> Function(
    String phone,
    String code,
    bool customer,
  )?
  authenticate;
  final bool customer;
  final String phone;
  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _seconds = 20;
  String? _error;
  bool _verified = false;
  Timer? _nextPage;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _seconds = 20;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _seconds = math.max(0, 20 - timer.tick));
      if (_seconds == 0) timer.cancel();
    });
  }

  void _resend() {
    if (_seconds != 0 || _verified || _authenticating) return;
    setState(() {
      _code.clear();
      _error = null;
      _startCountdown();
    });
    _focus.requestFocus();
  }

  bool _authenticating = false;
  Map<String, dynamic>? _account;
  Future<void> _verify() async {
    if (_verified || _authenticating) return;
    if (_code.text.length != 6) {
      setState(() => _error = '6 xonali kodni to‘liq kiriting');
      return;
    }
    if (_code.text != '111111') {
      setState(() => _error = 'Kod noto‘g‘ri. Qayta urinib ko‘ring.');
      _code.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _code.text.length,
      );
      _focus.requestFocus();
      return;
    }
    if (CustomerApi.enabled || widget.authenticate != null) {
      _focus.unfocus();
      setState(() {
        _authenticating = true;
        _error = null;
      });
      try {
        _account = widget.authenticate != null
            ? await widget.authenticate!(
                widget.phone,
                _code.text,
                widget.customer,
              )
            : await CustomerApi.login(
                widget.phone,
                _code.text,
                customer: widget.customer,
                isCurrent: () => mounted,
              );
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
        return;
      } finally {
        if (mounted) setState(() => _authenticating = false);
      }
      if (!mounted) return;
    }
    _timer?.cancel();
    _focus.unfocus();
    setState(() {
      _verified = true;
      _error = null;
    });
    final verifiedSession = CustomerApi.sessionVersion;
    final verifiedApi = CustomerApi.active;
    _nextPage = Timer(const Duration(milliseconds: 700), () {
      if (!mounted ||
          verifiedSession != CustomerApi.sessionVersion ||
          !identical(verifiedApi, CustomerApi.active)) {
        return;
      }
      if (_account != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) =>
                accountDestination(_account!, customer: widget.customer),
          ),
          (_) => false,
        );
        return;
      }
      if (widget.customer) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            // MyID is temporarily bypassed; the original route is retained.
            builder: (_) => myIdEnabled
                ? const MyIdPage(customer: true)
                : const CustomerRegistrationPage(),
          ),
          (_) => false,
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              myIdEnabled ? const MyIdPage() : const SitterRegistrationPage(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nextPage?.cancel();
    _focus.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    puppy: true,
    title: context.tr('SMS kodni kiriting'),
    subtitle: context
        .tr('otpDescription')
        .replaceAll(
          '{phone}',
          '+998 ** *** ** ${widget.phone.substring(widget.phone.length - 2)}',
        ),
    children: [
      SizedBox(
        height: 60,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: TextField(
                  key: const ValueKey('otpInput'),
                  controller: _code,
                  focusNode: _focus,
                  autofocus: true,
                  readOnly: _verified || _authenticating,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(color: Colors.transparent),
                  showCursor: false,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    labelText: context.tr('6 xonali SMS kod'),
                    labelStyle: TextStyle(color: Colors.transparent),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  onChanged: (value) {
                    setState(() => _error = null);
                    if (value.length == 6) _verify();
                  },
                  onSubmitted: (_) => _verify(),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Row(
                    children: List.generate(
                      6,
                      (i) => Expanded(
                        child: Container(
                          key: ValueKey('otpBox$i'),
                          margin: EdgeInsets.only(right: i == 5 ? 0 : 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9F1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              width: 1.6,
                              color: _verified
                                  ? const Color(0xFF4F8059)
                                  : _error != null
                                  ? Colors.red.shade700
                                  : i == _code.text.length
                                  ? AppColors.gold
                                  : const Color(0xFFC8AF91),
                            ),
                          ),
                          child: Text(
                            i < _code.text.length ? _code.text[i] : '',
                            style: authText(25, bold: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            context.tr(_error!),
            key: const ValueKey('otpError'),
            style: authText(14, color: Colors.red.shade700),
          ),
        ),
      const SizedBox(height: 16),
      if (!_verified) ...[
        AuthButton(
          key: const ValueKey('verifyOtp'),
          label: context.tr('Tasdiqlash'),
          loading: _authenticating,
          onPressed: _code.text.length == 6 ? _verify : null,
        ),
        const SizedBox(height: 12),
      ],
      if (!_verified)
        PressableButton.outlinedIcon(
          key: const ValueKey('resendCode'),
          onPressed: _seconds == 0 && !_authenticating ? _resend : null,
          icon: Icon(
            _seconds == 0 ? Icons.refresh_rounded : Icons.timer_outlined,
            size: 20,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            foregroundColor: AppColors.chocolate,
            backgroundColor: _seconds == 0
                ? AppColors.yellow
                : const Color(0xFFE6D9CA),
            disabledForegroundColor: AppColors.brown,
            side: BorderSide(
              color: _seconds == 0 ? AppColors.gold : const Color(0xFFC8AF91),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          label: Text(
            _seconds == 0
                ? context.tr('Kodni qayta jo‘natish')
                : '${context.tr('Qayta jo‘natish')} · 00:${_seconds.toString().padLeft(2, '0')}',
            style: authText(
              15,
              color: _seconds == 0 ? AppColors.chocolate : AppColors.brown,
            ),
          ),
        ),
      const SizedBox(height: 20),
    ],
  );
}

class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.puppy,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final bool puppy;
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return MomiqScaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.cream,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              right: 0,
              width: size.width * .36,
              height: size.height * .22,
              child: SvgPicture.asset(
                'assets/svg/decoration_top.svg',
                fit: BoxFit.fill,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              width: size.width * .4,
              height: size.height * .16,
              child: SvgPicture.asset(
                'assets/svg/decoration_bottom.svg',
                key: const ValueKey('authBottomDecoration'),
                fit: BoxFit.fill,
              ),
            ),
            SafeArea(
              maintainBottomViewPadding: true,
              child: Column(
                children: [
                  // The header never participates in keyboard scrolling.
                  Padding(
                    key: const ValueKey('authHeader'),
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: () => Navigator.of(context).maybePop(),
                              tooltip: context.tr('Orqaga'),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFE3D4C1),
                              ),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.chocolate,
                              ),
                            ),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  MomiqLogo(size: 30),
                                  const SizedBox(width: 8),
                                  Text('Momiq', style: momiqWordmark(26)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedPadding(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(
                        bottom: math.max(
                          0,
                          keyboard - MediaQuery.viewPaddingOf(context).bottom,
                        ),
                      ),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              children: [
                                AuthAnimal(
                                  puppy: puppy,
                                  size: math.min(size.width * .58, 245),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: authText(27, bold: true),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  subtitle,
                                  textAlign: TextAlign.center,
                                  style: authText(16, color: AppColors.brown),
                                ),
                                const SizedBox(height: 30),
                                ...children,
                              ],
                            ),
                          ),
                        ),
                      ),
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
}

class AuthAnimal extends StatelessWidget {
  const AuthAnimal({super.key, required this.puppy, required this.size});
  final bool puppy;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size * 2,
          maxWidth: size * 2,
          minHeight: size,
          maxHeight: size,
          alignment: puppy ? Alignment.centerRight : Alignment.centerLeft,
          child: Image.asset(
            'assets/images/auth_animals.png',
            width: size * 2,
            height: size,
            fit: BoxFit.fill,
          ),
        ),
      ),
    ),
  );
}

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: PressableButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.chocolate,
        minimumSize: const Size.fromHeight(58),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: const StadiumBorder(),
      ),
      child: ButtonProgress(
        loading: loading,
        child: Row(
          children: [
            const SizedBox(width: 38),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: authText(20, bold: true),
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
  );
}
