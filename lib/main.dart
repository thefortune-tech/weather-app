import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

// ==================== WEATHER MODEL ====================
class WeatherState {
  final String cityName;
  final double temperature;
  final int weatherCode;
  final double windspeed;
  final bool isFromCache;

  WeatherState({
    required this.cityName,
    required this.isFromCache,
    required this.temperature,
    required this.weatherCode,
    required this.windspeed,
  });

  WeatherState copyWith({
    String? cityName,
    double? temperature,
    int? weatherCode,
    double? windspeed,
    bool? isFromCache,
  }) {
    return WeatherState(
      cityName: cityName ?? this.cityName,
      isFromCache: isFromCache ?? this.isFromCache,
      temperature: temperature ?? this.temperature,
      weatherCode: weatherCode ?? this.weatherCode,
      windspeed: windspeed ?? this.windspeed,
    );
  }

  factory WeatherState.fromJson(Map<String, dynamic> json) {
    return WeatherState(
      cityName: json["cityName"],
      temperature: json["temperature"],
      weatherCode: json["weatherCode"],
      windspeed: json["windspeed"],
      isFromCache: json["isFromCache"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "cityName": cityName,
      "temperature": temperature,
      "weatherCode": weatherCode,
      "windspeed": windspeed,
      "isFromCache": isFromCache,
    };
  }
}

// ==================== WEATHER SERVICE ====================
class WeatherService {
  final Dio _dio = Dio();

  Future<Map<String, double>> getCoordinates(String cityName) async {
    final response = await _dio.get(
      'https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {'name': cityName, 'count': 1},
    );
    final result = response.data['results'][0];
    return {
      'lat': result['latitude'],
      'lon': result['longitude'],
    };
  }

  Future<WeatherState> getWeather(String cityName) async {
    final coords = await getCoordinates(cityName);
    final response = await _dio.get(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': coords['lat'],
        'longitude': coords['lon'],
        'current_weather': true,
      },
    );
    final current = response.data['current_weather'];
    return WeatherState(
      cityName: cityName,
      temperature: current['temperature'].toDouble(),
      weatherCode: current['weathercode'],
      windspeed: current['windspeed'].toDouble(),
      isFromCache: false,
    );
  }
}

// ==================== CACHE SERVICE ====================
class CacheService {
  static const String _boxName = "weatherbox";
  static const String _key = "lastWeather";

  Future<void> saveWeather(WeatherState weather) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_key, jsonEncode(weather.toJson()));
  }

  Future<WeatherState?> getWeather() async {
    final box = await Hive.openBox(_boxName);
    final data = box.get(_key);
    if (data == null) return null;
    return WeatherState.fromJson(jsonDecode(data));
  }
}

// ==================== WEATHER PROVIDER ====================
class WeatherNotifier extends AsyncNotifier<WeatherState?> {
  final WeatherService _weatherService = WeatherService();
  final CacheService _cacheService = CacheService();

  @override
  Future<WeatherState?> build() async {
    return await _cacheService.getWeather();
  }

  Future<void> fetchWeather(String cityName) async {
    state = const AsyncLoading();
    try {
      final weather = await _weatherService.getWeather(cityName);
      await _cacheService.saveWeather(weather);
      state = AsyncData(weather);
    } catch (e) {
      final cached = await _cacheService.getWeather();
      if (cached != null) {
        state = AsyncData(cached.copyWith(isFromCache: true));
      } else {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }
}

final weatherProvider = AsyncNotifierProvider<WeatherNotifier, WeatherState?>(
  () => WeatherNotifier(),
);

// ==================== WEATHER SCREEN ====================
class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  final TextEditingController _controller = TextEditingController();

  String _getWeatherIcon(int code) {
    if (code == 0) return '☀️';
    if (code <= 2) return '⛅';
    if (code <= 3) return '☁️';
    if (code <= 48) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    if (code <= 99) return '⛈️';
    return '🌡️';
  }

  String _getWeatherDescription(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 2) return 'Partly cloudy';
    if (code <= 3) return 'Overcast';
    if (code <= 48) return 'Foggy';
    if (code <= 67) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Rain showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final weatherState = ref.watch(weatherProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Search Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter city name...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      if (_controller.text.isNotEmpty) {
                        ref.read(weatherProvider.notifier).fetchWeather(_controller.text);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF378ADD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.search, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Weather Content
              Expanded(
                child: weatherState.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF378ADD)),
                  ),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('⛔', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load weather.\nNo cached data available.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  data: (weather) {
                    if (weather == null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🌍', style: TextStyle(fontSize: 64)),
                            const SizedBox(height: 16),
                            Text(
                              'Search for a city\nto see the weather',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return _buildWeatherContent(weather);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherContent(WeatherState weather) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (weather.isFromCache)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFAEEDA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️  Showing cached data',
                style: TextStyle(
                  color: Color(0xFF854F0B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            weather.cityName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getWeatherIcon(weather.weatherCode),
            style: const TextStyle(fontSize: 80),
          ),
          const SizedBox(height: 8),
          Text(
            _getWeatherDescription(weather.weatherCode),
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${weather.temperature.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF378ADD),
                    fontSize: 90,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(
                  text: '°C',
                  style: TextStyle(
                    color: Color(0xFF378ADD),
                    fontSize: 36,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  label: 'Wind speed',
                  value: '${weather.windspeed.toStringAsFixed(1)}',
                  unit: 'km/h',
                  icon: '💨',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  label: 'Weather code',
                  value: '${weather.weatherCode}',
                  unit: 'WMO',
                  icon: '📡',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String unit,
    required String icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== HIVE INIT ====================
Future<void> initHive() async {
  await Hive.initFlutter();
}

// ==================== MAIN ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Weather App",
      home: const WeatherScreen(),
    );
  }
}