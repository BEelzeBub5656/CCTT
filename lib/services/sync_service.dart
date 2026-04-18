import 'package:dio/dio.dart';
import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import 'settings_service.dart';

class SyncService {
  static Future<String> syncPendingRecords() async {
    final baseUrl = await SettingsService.getServerBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      return '请先点击右上角设置后端 API 地址';
    }

    final dbHelper = DatabaseHelper.instance;
    final allRecords = await dbHelper.getAllMovements();

    // 只要不是"已同步"，统统抓取出来重试（防止卡在 syncing/failed 状态）
    final pendingRecords = allRecords
        .where((r) => r.syncStatus != SyncStatus.synced)
        .toList();

    if (pendingRecords.isEmpty) {
      return '当前没有需要同步的记录';
    }

    final ids = pendingRecords.map((e) => e.id).toList();

    // 发送前，先将数据库状态更新为 "正在同步"
    await dbHelper.updateSyncStatus(ids, SyncStatus.syncing);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    try {
      // 数据转换移入 try-catch，防止转换报错导致状态未复位
      final payload = pendingRecords.map((e) => e.toJson()).toList();
      final response = await dio.post('/api/sync', data: payload);

      if (response.statusCode == 200) {
        // 成功后，更新为 "已同步"
        await dbHelper.updateSyncStatus(ids, SyncStatus.synced);
        return '成功同步 ${pendingRecords.length} 条记录';
      } else {
        // HTTP 状态码错误
        await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
        return '服务器返回异常代码: ${response.statusCode}';
      }
    } on DioException catch (e) {
      await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return '连接超时，请检查网络或 Tailscale/Pinggy 状态';
      }
      return '网络请求异常: ${e.message}';
    } catch (e) {
      // 如果代码本身有 Bug，会在这里被抓出并显示！
      await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
      return '本地代码执行崩溃: $e';
    }
  }
}
