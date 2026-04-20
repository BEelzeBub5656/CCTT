import 'package:shared_preferences/shared_preferences.dart';

/// 本地配置持久化服务
///
/// 封装 [SharedPreferences] 的读写操作，提供类型安全的静态方法。
class SettingsService {
  static const _kServerBaseUrl = 'server_base_url';

  // MQTT 配置 keys
  static const _kMqttBroker = 'mqtt_broker';
  static const _kMqttPort = 'mqtt_port';
  static const _kMqttUsername = 'mqtt_username';
  static const _kMqttPassword = 'mqtt_password';

  // 交互配置 keys
  static const _kLongPressDuration = 'long_press_duration';

  // ───────────── 后端地址（兼容旧版 Dio 配置）─────────────

  static Future<String?> getServerBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kServerBaseUrl);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  static Future<String?> getNormalizedServerBaseUrl() async {
    final url = await getServerBaseUrl();
    if (url == null) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return 'http://$url';
  }

  static Future<void> setServerBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerBaseUrl, url.trim());
  }

  // ───────────── MQTT 配置 ─────────────

  static Future<String> getMqttBroker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMqttBroker) ?? 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
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

  // ───────────── 长按确认时间 ─────────────

  /// 读取长按确认时间（秒），默认 3.0
  static Future<double> getLongPressDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kLongPressDuration) ?? 3.0;
  }

  static Future<void> setLongPressDuration(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLongPressDuration, value);
  }
}
