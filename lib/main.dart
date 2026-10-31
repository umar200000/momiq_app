import 'core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'core/config/app_environment.dart';
import 'features/profile/presentation/profile_export_tile.dart' show clearInterruptedProfileExports;

import 'core/theme/app_colors.dart';
import 'features/splash/presentation/pages/splash_page.dart';

Stream<LicenseEntry> bundledFontLicenses() async* {
  const files = {
    'Quicksand': 'assets/fonts/OFL.txt',
    'Baloo 2': 'assets/fonts/Baloo2-OFL.txt',
  };
  for (final entry in files.entries) {
    yield LicenseEntryWithLineBreaks(
      [entry.key],
      await rootBundle.loadString(entry.value),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.current.validate(release: kReleaseMode);
  LicenseRegistry.addLicense(bundledFontLicenses);
  await clearInterruptedProfileExports();
  await AppLanguage.restore();
  runApp(AppLanguage(child: const Momiq()));
}

class Momiq extends StatelessWidget {
  const Momiq({super.key});

  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLanguage>();
    return MaterialApp(
      locale: Locale(AppLanguage.current.value),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('uz'), Locale('en'), Locale('ru')],
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
