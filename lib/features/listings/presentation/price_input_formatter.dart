import 'package:flutter/services.dart';

class PriceInputFormatter extends TextInputFormatter {
  const PriceInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 9) return oldValue;
    final formatted = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]} ',
    );
    int offset(int sourceOffset) {
      if (sourceOffset < 0) return formatted.length;
      final count = newValue.text
          .substring(0, sourceOffset)
          .replaceAll(RegExp(r'\D'), '')
          .length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ' ' && ++seen == count) return i + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
    );
  }
}
