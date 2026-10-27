import 'core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/config/app_environment.dart';

import 'core/theme/app_colors.dart';
import 'features/splash/presentation/pages/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.current.validate(release: kReleaseMode);
  await AppLanguage.restore();
  runApp(AppLanguage(child: const Momiq()));
}

class Momiq extends StatelessWidget {
  const Momiq({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Momiq',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AppEnvironment.current.name == 'production'
          ? child!
          : Banner(
              message: AppEnvironment.current.name.toUpperCase(),
              location: BannerLocation.topEnd,
              child: child!,
            ),
      theme: ThemeData(
        fontFamily: 'Quicksand',
        scaffoldBackgroundColor: AppColors.cream,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.gold),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}
