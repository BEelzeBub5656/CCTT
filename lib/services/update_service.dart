import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'settings_service.dart';

/// 云端 `/api/version` 接口使用的版本信息。
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

  const VersionInfo({
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
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      versionName: json['versionName'] as String? ?? '',
      buildTime: (json['buildTime'] as num?)?.toInt() ?? 0,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      md5: json['md5'] as String? ?? '',
      changelog: (json['changelog'] as List<dynamic>?)
              ?.map((entry) => entry.toString())
              .toList() ??
          const [],
      forceUpdate: json['forceUpdate'] == true,
      minVersion: (json['minVersion'] as num?)?.toInt() ?? 1,
    );
  }

  String get fileSizeFormatted {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 云端版本接口的检查结果，供自动下载安装对话框使用。
class ServerUpdateCheckResult {
  final bool hasUpdate;
  final bool forceUpdate;
  final VersionInfo? latest;
  final String message;

  const ServerUpdateCheckResult({
    required this.hasUpdate,
    required this.forceUpdate,
    this.latest,
    required this.message,
  });
}

class AppVersionInfo {
  final String versionName;
  final int versionCode;

  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
  });

  String get displayText => '$versionName+$versionCode';
}

/// 本地服务器版本清单 `/api/app-update/latest` 的内容。
class AppReleaseInfo {
  final String versionName;
  final int versionCode;
  final bool mandatory;
  final String? apkUrl;
  final String sha256;
  final String releaseNotes;
  final DateTime? publishedAt;
  final bool available;

  const AppReleaseInfo({
    required this.versionName,
    required this.versionCode,
    required this.mandatory,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
    required this.available,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    final versionName = json['versionName'] as String? ?? '';
    final versionCode = (json['versionCode'] as num?)?.toInt() ?? 0;
    if (versionName.isEmpty || versionCode <= 0) {
      throw const FormatException('版本清单缺少有效的版本号');
    }

    final rawApkUrl = (json['apkUrl'] as String?)?.trim();
    return AppReleaseInfo(
      versionName: versionName,
      versionCode: versionCode,
      mandatory: json['mandatory'] == true,
      apkUrl: rawApkUrl == null || rawApkUrl.isEmpty ? null : rawApkUrl,
      sha256: json['sha256'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      available: json['available'] == true,
    );
  }
}

/// 可配置版本清单接口的检查结果，供设置页和本地服务器阶段使用。
class UpdateCheckResult {
  final AppVersionInfo current;
  final AppReleaseInfo latest;

  const UpdateCheckResult({required this.current, required this.latest});

  bool get hasUpdate => latest.versionCode > current.versionCode;
  bool get canDownload =>
      hasUpdate && latest.available && latest.apkUrl != null;
}

class UpdateService {
  const UpdateService._();

  static const String _cloudBaseUrl = 'https://www.beelzebub.top/api/version';

  /// 随当前 APK 固定发布，供设置页随时查看本版本声明。
  static const List<String> currentReleaseNotes = [
    '支持拍照识别每日生产记录，按日期生成多张本厂生产入库单',
    '批量填写一次品名并应用到全部日期，生产入库允许零单价',
    '保留逐日审核和手动修改，自动核对日产量与月度合计',
    '升级后安全清理 OCR 临时图片和旧 APK，不触碰业务数据',
  ];

  /// 检查 GitHub Actions 部署到云服务器的版本。
  static Future<ServerUpdateCheckResult> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = int.tryParse(packageInfo.buildNumber) ?? 0;
      final response = await http
          .get(Uri.parse('$_cloudBaseUrl/check?currentVersion=$currentVersion'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('服务器返回错误: ${response.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['message'] ?? '检查更新失败');
      }

      VersionInfo? latest;
      if (data['hasUpdate'] == true && data['latest'] != null) {
        latest = VersionInfo.fromJson(data['latest'] as Map<String, dynamic>);
      }
      return ServerUpdateCheckResult(
        hasUpdate: data['hasUpdate'] == true,
        forceUpdate: data['forceUpdate'] == true,
        latest: latest,
        message: data['message'] as String? ?? '',
      );
    } catch (error) {
      return ServerUpdateCheckResult(
        hasUpdate: false,
        forceUpdate: false,
        message: '检查更新失败: $error',
      );
    }
  }

  static Future<VersionInfo?> getLatestVersion() async {
    try {
      final response = await http
          .get(Uri.parse('$_cloudBaseUrl/latest'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['success'] == true && data['data'] != null) {
        return VersionInfo.fromJson(data['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<AppVersionInfo> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      versionName: packageInfo.version,
      versionCode: int.tryParse(packageInfo.buildNumber) ?? 0,
    );
  }

  static Future<Map<String, String>> getCurrentPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return {
      'appName': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
    };
  }

  /// 检查可配置的本地版本清单，便于云服务器接入前调试。
  static Future<UpdateCheckResult> checkForUpdate({String? manifestUrl}) async {
    final url =
        (manifestUrl ?? await SettingsService.getUpdateManifestUrl()).trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const UpdateException('更新清单地址无效');
    }

    try {
      final current = await getCurrentVersion();
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw UpdateException('服务器返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('版本清单格式无效');
      }
      return evaluate(
        current: current,
        latest: AppReleaseInfo.fromJson(decoded),
      );
    } on UpdateException {
      rethrow;
    } on FormatException catch (error) {
      throw UpdateException(error.message);
    } catch (error) {
      throw UpdateException('检查更新失败：$error');
    }
  }

  static UpdateCheckResult evaluate({
    required AppVersionInfo current,
    required AppReleaseInfo latest,
  }) {
    return UpdateCheckResult(current: current, latest: latest);
  }
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}
