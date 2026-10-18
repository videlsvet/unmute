class AppConfig {
  /// Primary API Gateway URL from Wave Android app
  static const String apiGatewayUrl =
      'https://d5dn6r204cm4tpgfe0ms.kf69zffa.apigw.yandexcloud.net/search';

  /// Direct Yandex Cloud function URL (fallback)
  static const String searchBaseUrl =
      'https://functions.yandexcloud.net/d4e09khm9p5t3cu2oq22';

  /// Auth, Favorites, and Profile Cloud Function URL
  static const String authBaseUrl =
      'https://functions.yandexcloud.net/d4e55oqrims414ecgmtd';
}