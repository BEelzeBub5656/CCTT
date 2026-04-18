import 'package:shared_preferences/shared_preferences.dart';

/// 本地配置持久化服务
///
/// 封装 [SharedPreferences] 的读写操作，提供类型安全的静态方法。
class SettingsService {
  static const _kServerBaseUrl = 'server_base_url';

  /// 读取已保存的后端地址（原始值）
  ///
  /// 若用户未配置或为空，返回 null。
  static Future<String?> getServerBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kServerBaseUrl);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  /// 读取后端地址并自动补全协议头
  ///
  /// - 若用户未配置，返回 null
  /// - 若地址不含协议头，自动补全 `http://`
  static Future<String?> getNormalizedServerBaseUrl() async {
    final url = await getServerBaseUrl();
    if (url == null) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return 'http://$url';
  }

  /// 保存后端地址
  static Future<void> setServerBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerBaseUrl, url.trim());
  }
}
