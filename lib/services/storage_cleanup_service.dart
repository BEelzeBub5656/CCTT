import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仅清理 App 自己生成且可重新生成的临时文件。
///
/// 业务数据库、单据照片、离线包和待同步数据均不在清理范围内。
class StorageCleanupService {
  const StorageCleanupService._();

  static const _lastCleanupBuildKey = 'last_safe_cleanup_build';
  static final _ocrTempFilePattern = RegExp(
    r'^ocr_[0-9a-f-]+\.(?:jpg|jpeg|png)$',
    caseSensitive: false,
  );
  static final _updateApkPattern = RegExp(
    r'^cctt-[0-9a-z._+-]+\.apk$',
    caseSensitive: false,
  );

  /// 每个 build 首次启动时执行一次安全清理。
  static Future<CleanupResult> runAfterUpgrade() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final buildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getInt(_lastCleanupBuildKey) == buildNumber) {
      return const CleanupResult(skipped: true);
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    Directory? externalDirectory;
    if (Platform.isAndroid) {
      try {
        externalDirectory = await getExternalStorageDirectory();
      } catch (_) {
        // 外部应用目录不可用时仍可继续清理 OCR 临时图片。
      }
    }

    final result = await cleanupManagedFiles(
      documentsDirectory: documentsDirectory,
      externalDirectory: externalDirectory,
    );
    await preferences.setInt(_lastCleanupBuildKey, buildNumber);
    return result;
  }

  /// 清理已知目录中的已知文件名，不递归、不跟随链接。
  static Future<CleanupResult> cleanupManagedFiles({
    required Directory documentsDirectory,
    Directory? externalDirectory,
  }) async {
    final ocrResult = await _deleteMatchingFiles(
      Directory(p.join(documentsDirectory.path, 'ocr_temp')),
      _ocrTempFilePattern,
    );
    final apkResult = externalDirectory == null
        ? const CleanupResult()
        : await cleanupUpdatePackages(externalDirectory);
    return ocrResult + apkResult;
  }

  /// 下载新版本前清除应用专属目录中的旧 CCTT 安装包。
  static Future<CleanupResult> cleanupUpdatePackages(
    Directory directory,
  ) =>
      _deleteMatchingFiles(directory, _updateApkPattern);

  static Future<CleanupResult> _deleteMatchingFiles(
    Directory directory,
    RegExp fileNamePattern,
  ) async {
    if (!await directory.exists()) return const CleanupResult();

    var deletedFiles = 0;
    var failedFiles = 0;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !fileNamePattern.hasMatch(p.basename(entity.path))) {
          continue;
        }
        try {
          await entity.delete();
          deletedFiles++;
        } catch (_) {
          failedFiles++;
        }
      }
    } catch (_) {
      failedFiles++;
    }
    return CleanupResult(
      deletedFiles: deletedFiles,
      failedFiles: failedFiles,
    );
  }
}

class CleanupResult {
  final bool skipped;
  final int deletedFiles;
  final int failedFiles;

  const CleanupResult({
    this.skipped = false,
    this.deletedFiles = 0,
    this.failedFiles = 0,
  });

  CleanupResult operator +(CleanupResult other) => CleanupResult(
        skipped: skipped && other.skipped,
        deletedFiles: deletedFiles + other.deletedFiles,
        failedFiles: failedFiles + other.failedFiles,
      );
}
