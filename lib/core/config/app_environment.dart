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
    if (name == 'local') {
      if (release) throw StateError('Local configuration cannot be released');
      if (url.host == 'api.momiq.net') {
        throw StateError('Local builds cannot use the production API');
      }
    } else if (url.scheme != 'https' ||
        {'localhost', '127.0.0.1', '::1'}.contains(url.host)) {
      throw StateError('Hosted builds require HTTPS and a remote API');
    }
    if (name == 'production' && url.host != 'api.momiq.net') {
      throw StateError('Production builds must use the production API');
    }
    if (name == 'staging' && url.host == 'api.momiq.net') {
      throw StateError('Staging must not use the production API');
    }
  }

  void validateHealth(Map<String, dynamic> health) {
    if (health['mode'] != name) {
      throw StateError('Ilova va server muhiti mos emas.');
    }
    if (name == 'production' &&
        (health['testLogin'] != false || health['sms'] != true)) {
      throw StateError('Production kirish xizmati hali tayyor emas.');
    }
  }
}
