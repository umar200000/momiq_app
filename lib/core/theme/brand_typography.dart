import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Shared wordmark styling, independent of the interface typography.
TextStyle momiqWordmark(double size) => TextStyle(
  fontFamily: 'MomiqBrand',
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: AppColors.chocolate,
  height: 1.15,
  letterSpacing: -size * .025,
);
