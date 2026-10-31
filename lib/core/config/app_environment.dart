import 'dart:io' show InternetAddress;

/// Explicit build environment; release builds must opt into their destination.
class AppEnvironment {
  const AppEnvironment(this.name, this.apiUrl);

  static const current = AppEnvironment(
    String.fromEnvironment('MOMIQ_ENV', defaultValue: 'local'),
    String.fromEnvironment(
      'MOMIQ_API_URL',
      defaultValue: 'http://127.0.0.1:8080/api',
    ),
  );

  final String name, apiUrl;
  static const requiredMobileFeatures = {
    'booking-receipts-v1',
    'home-visit-address-v1',
    'wallet-receipts-v1',
    'support-receipts-v1',
    'private-video-report-v1',
    'notice-read-receipts-v1',
  };
  String get sessionScope => '$name|$apiUrl';

  void validate({
    bool release = false,
    bool apiEnabled = const bool.fromEnvironment(
      'MOMIQ_API_ENABLED',
      defaultValue: true,
    ),
  }) {
    if (!{'local', 'staging', 'production'}.contains(name)) {
      throw StateError('Unknown MOMIQ_ENV');
    }
    if (name != 'local' && !apiEnabled) {
      throw StateError('Hosted builds cannot disable the server API');
    }
    final url = Uri.tryParse(apiUrl);
    if (url == null ||
        !url.hasAuthority ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        url.path != '/api' ||
        !{'http', 'https'}.contains(url.scheme)) {
      throw StateError('MOMIQ_API_URL must be an API origin ending in /api');
    }
    final host = url.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (name == 'local') {
      if (release) throw StateError('Local configuration cannot be released');
      if (host == 'api.momiq.net') {
        throw StateError('Local builds cannot use the production API');
      }
    } else if (url.scheme != 'https' ||
        _localDestination(host) ||
        host.endsWith('.invalid')) {
      throw StateError('Hosted builds require HTTPS and a remote API');
    }
    if (name == 'production' &&
        (url.host != 'api.momiq.net' || url.port != 443)) {
      throw StateError('Production builds must use the production API');
    }
    if (name == 'staging' && host == 'api.momiq.net') {
      throw StateError('Staging must not use the production API');
    }
  }

  static bool _localDestination(String host) {
    if (host.isEmpty || host == 'localhost' || host.endsWith('.localhost')) {
      return true;
    }
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      // Legacy numeric host spellings can resolve as IPv4 without a DNS lookup.
      return RegExp(
        r'^(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+)){0,3}$',
      ).hasMatch(host);
    }
    final bytes = ip.rawAddress;
    if (ip.isLoopback || bytes.every((b) => b == 0)) return true;
    if (bytes.length == 16 &&
        bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return bytes[12] == 127 || bytes.skip(12).every((b) => b == 0);
    }
    return false;
  }

  void validateHealth(Map<String, dynamic> health) {
    if (health['mode'] != name || (name != 'local' && health['ok'] != true)) {
      throw StateError('Ilova va server muhiti mos emas.');
    }
    if (name == 'production' &&
        (health['testLogin'] != false || health['sms'] != true)) {
      throw StateError('Production kirish xizmati hali tayyor emas.');
    }
    final features = health['mobileFeatures'];
    if (name != 'local' &&
        (features is! List ||
            !requiredMobileFeatures.every(features.contains))) {
      throw StateError('Server versiyasi ilovaga mos emas.');
    }
  }
}
