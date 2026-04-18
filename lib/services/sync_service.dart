import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';

/// SharedPreferences Key，用于存储后端地址
const _kServerBaseUrl = 'server_base_url';

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
      const SyncResult._(false, '后端地址未配置，请在设置中配置 PC 地址', 0);
}

/// P2P 同步服务
///
/// 负责将本地 [SyncStatus.pending] 的库存移动记录批量推送到 PC 后端 API。
class SyncService {
  final Dio? _dio;
  final DatabaseHelper _db;

  SyncService({Dio? dio, DatabaseHelper? db})
      : _dio = dio,
        _db = db ?? DatabaseHelper.instance;

  /// 从 SharedPreferences 读取并解析后端地址
  ///
  /// - 若用户未配置，返回 null
  /// - 若地址不含协议头，自动补全 http://
  static Future<String?> _resolveBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kServerBaseUrl);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    var url = raw.trim();
    // 自动补全协议头
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  /// 探测并同步
  ///
  /// 1. 查询所有 pending 记录
  /// 2. 若无记录，直接返回 [SyncResult.empty]
  /// 3. 向后端 POST /api/sync（JSON 数组）
  /// 4. 若成功，批量将本地记录状态更新为 [SyncStatus.synced]
  /// 5. 若超时或连接失败，返回 [SyncResult.offline]
  Future<SyncResult> syncPendingRecords() async {
    // 1. 解析动态后端地址
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) {
      return SyncResult.notConfigured();
    }

    // 2. 创建或复用 Dio 实例
    // 注意：字段的空安全无法自动提升，需先赋值给局部变量
    final Dio dio;
    final existingDio = _dio;
    if (existingDio != null) {
      dio = existingDio;
      dio.options.baseUrl = baseUrl;
    } else {
      dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ));
    }

    final pending = await _db.getPendingMovements();
    if (pending.isEmpty) {
      return SyncResult.empty();
    }

    try {
      final response = await dio.post<List<dynamic>>(
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
