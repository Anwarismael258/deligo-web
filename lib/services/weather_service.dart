import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';

class WeatherSnapshot {
  final String cityName;
  final double temperatureC;
  final String condition;
  final String iconCode;

  const WeatherSnapshot({
    required this.cityName,
    required this.temperatureC,
    required this.condition,
    required this.iconCode,
  });
}

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  Future<WeatherSnapshot?> fetchWeather({
    double? latitude,
    double? longitude,
    String? city,
  }) async {
    final apiKey = AppEnv.openWeatherApiKey;
    if (apiKey.isEmpty) return null;

    try {
      final query = <String, String>{
        'appid': apiKey,
        'units': 'metric',
        'lang': 'pt_br',
      };

      if (latitude != null && longitude != null) {
        query['lat'] = latitude.toString();
        query['lon'] = longitude.toString();
      } else if (city != null && city.trim().isNotEmpty) {
        query['q'] = city.trim();
      } else {
        return null;
      }

      final uri = Uri.https(
        'api.openweathermap.org',
        '/data/2.5/weather',
        query,
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final weatherList =
          (data['weather'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final weather = weatherList.isNotEmpty ? weatherList.first : const {};
      final temp = (data['main'] as Map<String, dynamic>?)?['temp'];

      return WeatherSnapshot(
        cityName: data['name']?.toString().trim().isNotEmpty == true
            ? data['name'].toString().trim()
            : (city?.trim().isNotEmpty == true ? city!.trim() : 'Sua cidade'),
        temperatureC: (temp as num?)?.toDouble() ?? 0,
        condition: weather['description']?.toString() ?? 'Tempo limpo',
        iconCode: weather['icon']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('WeatherService.fetchWeather error: $e');
      return null;
    }
  }
}
