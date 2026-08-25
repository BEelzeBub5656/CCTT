import 'package:cctt/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析版本清单并识别新版本', () {
    final release = AppReleaseInfo.fromJson({
      'versionName': '1.1.0',
      'versionCode': 2,
      'mandatory': false,
      'apkUrl': 'https://example.com/cctt.apk',
      'sha256': 'abc',
      'releaseNotes': '新增汇总功能',
      'publishedAt': '2026-08-22T00:00:00+08:00',
      'available': true,
    });
    final result = UpdateService.evaluate(
      current: const AppVersionInfo(versionName: '1.0.0', versionCode: 1),
      latest: release,
    );

    expect(result.hasUpdate, isTrue);
    expect(result.canDownload, isTrue);
    expect(result.latest.releaseNotes, '新增汇总功能');
  });

  test('相同 versionCode 不视为新版本', () {
    final release = AppReleaseInfo.fromJson({
      'versionName': '1.0.0',
      'versionCode': 1,
      'mandatory': false,
      'apkUrl': null,
      'available': false,
    });
    final result = UpdateService.evaluate(
      current: const AppVersionInfo(versionName: '1.0.0', versionCode: 1),
      latest: release,
    );

    expect(result.hasUpdate, isFalse);
    expect(result.canDownload, isFalse);
  });

  test('无效版本清单会被拒绝', () {
    expect(
      () => AppReleaseInfo.fromJson({
        'versionName': '',
        'versionCode': 0,
      }),
      throwsFormatException,
    );
  });
}
