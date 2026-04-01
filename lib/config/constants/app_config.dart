// lib/config/constants/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get baseUrl {
    final url = dotenv.env['BASE_URL'];

    if (url == null || url.isEmpty) {
      throw Exception('BASE_URL not found in .env');
    }

    return url;
  }

  static String checkInUrl(String hospitalId) {
    debugPrint('BASE URL: ${AppConfig.baseUrl}');
    return '${AppConfig.baseUrl}/#/checkin/$hospitalId';
  }
}
