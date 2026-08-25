import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 版本信息
class VersionInfo {
  final int versionCode;
  final String versionName;
  final int buildTime;
  final String downloadUrl;
  final int fileSize;
  final String md5;
  final List<String> changelog;
  final bool forceUpdate;
  final int minVersion;

  VersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.buildTime,
    required this.downloadUrl,
    required this.fileSize,
    required this.md5,
    required this.changelog,
    required this.forceUpdate,
    required this.minVersion,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      versionCode: json['versionCode'] as int,
      versionName: json['versionName'] as String,
      buildTime: json['buildTime'] as int,
      downloadUrl: json['downloadUrl'] as String,
      fileSize: json['fileSize'] as int? ?? 0,
      md5: json['md5'] as String? ?? '',
      changelog: (json['changelog'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      minVersion: json['minVersion'] as int? ?? 1,
    );
  }

  String get fileSizeFormatted {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final bool forceUpdate;
  final VersionInfo? latest;
  final String message;

  UpdateCheckResult({
    required this.hasUpdate,
    required this.forceUpdate,
    this.latest,
    required this.message,
  });
}

/// 自动更新服务
class UpdateService {
  static const String _baseUrl = 'https://www.beelzebub.top/api/version';

  /// 检查更新
  static Future<UpdateCheckResult> checkUpdate() async {
    try {
      // 获取当前APP版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 请求服务器检查更新
      final response = await http.get(
        Uri.parse('$_baseUrl/check?currentVersion=$currentVersion'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('服务器返回错误: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] != true) {
        throw Exception(data['message'] ?? '检查更新失败');
      }

      final hasUpdate = data['hasUpdate'] as bool? ?? false;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final message = data['message'] as String? ?? '';

      VersionInfo? latest;
      if (hasUpdate && data['latest'] != null) {
        latest = VersionInfo.fromJson(data['latest'] as Map<String, dynamic>);
      }

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        forceUpdate: forceUpdate,
        latest: latest,
        message: message,
      );
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        forceUpdate: false,
        message: '检查更新失败: $e',
      );
    }
  }

  /// 获取最新版本信息
  static Future<VersionInfo?> getLatestVersion() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/latest'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true && data['data'] != null) {
        return VersionInfo.fromJson(data['data'] as Map<String, dynamic>);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取当前APP版本信息
  static Future<Map<String, String>> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return {
      'appName': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
    };
  }
}
