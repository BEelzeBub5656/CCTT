import 'package:dio/dio.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';

/// 同步结果封装
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;

  const SyncResult._(this.success, this.message, this.syncedCount);

  factory SyncResult.empty() =>
      const SyncResult._(true, '没有待同步的记录', 0);

  factory SyncResult.success(int count) =>
      SyncResult._(true, '成功同步 $count 条记录', count);

  factory SyncResult.offline(String reason) =>
      SyncResult._(false, '后端不可达：$reason', 0);

  factory SyncResult.failure(String reason) =>
      SyncResult._(false, '同步失败：$reason', 0);

  factory SyncResult.notConfigured() =>
      const SyncResult._(false, '后端地址未配置，请在代码中修改 _baseUrl 为真实 IP', 0);
}

/// P2P 同步服务
///
/// 负责将本地 [SyncStatus.pending] 的库存移动记录批量推送到 PC 后端 API。
class SyncService {
  /// ⚠️ 请将 '100.x.x.x' 替换为你的 PC 在 Tailscale/WireGuard 中的真实虚拟 IP
  static const String _baseUrl = 'http://100.x.x.x:3000';

  final Dio _dio;
  final DatabaseHelper _db;

  SyncService({Dio? dio, DatabaseHelper? db})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            )),
        _db = db ?? DatabaseHelper.instance;

  /// 探测并同步
  ///
  /// 1. 查询所有 pending 记录
  /// 2. 若无记录，直接返回 [SyncResult.empty]
  /// 3. 向后端 POST /api/sync（JSON 数组）
  /// 4. 若成功，批量将本地记录状态更新为 [SyncStatus.synced]
  /// 5. 若超时或连接失败，返回 [SyncResult.offline]
  Future<SyncResult> syncPendingRecords() async {
    // 占位符检测：如果地址仍是默认值，直接提示未配置
    if (_baseUrl.contains('100.x.x.x')) {
      return SyncResult.notConfigured();
    }

    final pending = await _db.getPendingMovements();
    if (pending.isEmpty) {
      return SyncResult.empty();
    }

    try {
      final response = await _dio.post<List<dynamic>>(
        '/api/sync',
        data: pending.map((r) => r.toJson()).toList(),
      );

      if (response.statusCode == 200) {
        for (final record in pending) {
          await _db.updateMovementSyncStatus(record.id, SyncStatus.synced);
        }
        return SyncResult.success(pending.length);
      } else {
        return SyncResult.failure(
          '服务器返回 HTTP ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.sendTimeout) {
        return SyncResult.offline('请求超时或无法连接 PC');
      }
      if (e.type == DioExceptionType.unknown) {
        // 常见场景：IP 不可达、DNS 解析失败、网络未连接
        final errMsg = e.message ?? '';
        if (errMsg.contains('SocketException') ||
            errMsg.contains('Connection refused') ||
            errMsg.contains('No route to host') ||
            errMsg.contains('Network is unreachable')) {
          return SyncResult.offline('无法连接到 PC，请检查网络或后端是否运行');
        }
        return SyncResult.failure('网络异常：$errMsg');
      }
      return SyncResult.failure(e.message ?? '未知网络错误');
    } catch (e) {
      return SyncResult.failure(e.toString());
    }
  }
}
