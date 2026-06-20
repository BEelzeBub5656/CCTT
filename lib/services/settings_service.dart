import 'package:shared_preferences/shared_preferences.dart';

/// 本地配置持久化服务
///
/// 封装 [SharedPreferences] 的读写操作，提供类型安全的静态方法。
class SettingsService {
  // Keys
  static const _kMqttBroker = 'mqtt_broker';
  static const _kMqttPort = 'mqtt_port';
  static const _kMqttUsername = 'mqtt_username';
  static const _kMqttPassword = 'mqtt_password';
  static const _kOcrServerUrl = 'ocr_server_url';

  // ───────────── MQTT 配置 ─────────────

  static Future<String> getMqttBroker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMqttBroker) ??
        'kf33d077.ala.cn-hangzhou.emqxsl.cn';
  }

  static Future<int> getMqttPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kMqttPort) ?? 8883;
  }

  static Future<String> getMqttUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMqttUsername) ?? 'BEelzeBub';
  }

  static Future<String> getMqttPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMqttPassword) ?? '20050805jycPP';
  }

  static Future<void> setMqttBroker(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMqttBroker, value.trim());
  }

  static Future<void> setMqttPort(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMqttPort, value);
  }

  static Future<void> setMqttUsername(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMqttUsername, value.trim());
  }

  static Future<void> setMqttPassword(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMqttPassword, value.trim());
  }

  // ───────────── OCR 配置 ─────────────

  static Future<String> getOcrServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOcrServerUrl) ?? 'https://www.beelzebub.top';
  }

  static Future<void> setOcrServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOcrServerUrl, value.trim());
  }
}
