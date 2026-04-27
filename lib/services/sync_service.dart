import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import 'settings_service.dart';

/// 拉取快照的结果
class PullResult {
  final bool success;
  final int addedCount;
  final int warehouseCount;
  final String message;

  const PullResult({
    required this.success,
    required this.addedCount,
    required this.warehouseCount,
    required this.message,
  });
}

/// MQTT 同步服务
///
/// 负责将本地 [SyncStatus.pending] / [SyncStatus.failed] 的库存移动记录
/// 通过 MQTT over TLS 发布到 EMQX Broker，同时支持从云端拉取全量快照。
///
/// **异常安全原则**：所有网络操作都在 try-catch 中，[client.disconnect] 在 finally 中
/// 无条件调用，防止任何情况下 MQTT 连接挂起或泄漏。
class SyncService {
  static const _publishTopic = 'cctt/sync/inbound';
  static const _snapshotTopic = 'cctt/sync/snapshot';

  /// 从 SettingsService 读取动态 MQTT 配置
  static Future<MqttServerClient> _createClient() async {
    final broker = await SettingsService.getMqttBroker();
    final port = await SettingsService.getMqttPort();
    final clientId = const Uuid().v4();
    final client = MqttServerClient(broker, clientId);
    client.port = port;
    client.secure = true;
    client.setProtocolV311();
    client.logging(on: false);
    return client;
  }

  static Future<Map<String, String>> _getCredentials() async {
    return {
      'username': await SettingsService.getMqttUsername(),
      'password': await SettingsService.getMqttPassword(),
    };
  }

  /// 发布本地待同步记录到云端（包含 records + warehouses）
  ///
  /// 异常安全：任何步骤抛出异常都会回滚状态为 [SyncStatus.failed]，
  /// 并在 [finally] 中确保 [client.disconnect]。
  static Future<String> syncPendingRecords() async {
    final dbHelper = DatabaseHelper.instance;
    final allRecords = await dbHelper.getAllMovements();

    final pendingRecords = allRecords
        .where((r) => r.syncStatus != SyncStatus.synced)
        .toList();
    if (pendingRecords.isEmpty) {
      return '当前没有需要同步的记录';
    }

    final ids = pendingRecords.map((e) => e.id).toList();
    await dbHelper.updateSyncStatus(ids, SyncStatus.syncing);

    // 收集全量仓库（快照恢复需要完整仓库列表，不能只打包关联仓库）
    final allWarehouses = await dbHelper.getAllWarehouses();

    MqttServerClient? client;
    try {
      client = await _createClient();
      final creds = await _getCredentials();
      await client.connect(creds['username']!, creds['password']!);

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
          'MQTT 连接失败: ${client.connectionStatus?.returnCode}',
        );
      }

      // 打包 records + 全量 warehouses（云端快照恢复依赖完整仓库列表）
      final payload = jsonEncode({
        'records': pendingRecords.map((e) => e.toJson()).toList(),
        'warehouses': allWarehouses.map((e) => e.toJson()).toList(),
      });

      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);
      client.publishMessage(
        _publishTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      await dbHelper.updateSyncStatus(ids, SyncStatus.synced);
      return '成功同步 ${pendingRecords.length} 条记录';
    } catch (e) {
      await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
      return '同步失败: $e';
    } finally {
      client?.disconnect();
    }
  }

  /// 从云端拉取 retain 全量快照并写入本地数据库
  ///
  /// 解析 JSON 时，所有字段均有绝对安全的空检查，
  /// 防止 `type 'Null' is not a subtype of type '...'` 运行时崩溃。
  ///
  /// 本地优先策略：使用 [ConflictAlgorithm.ignore]，云端数据仅在本地不存在时才插入，
  /// 已存在的本地记录绝不覆盖。
  ///
  /// **异常安全原则**：监听 updates 设 5 秒超时，任何异常都在 finally 中 disconnect。
  static Future<PullResult> pullSnapshot() async {
    final dbHelper = DatabaseHelper.instance;
    MqttServerClient? client;

    // 拉取前统计本地记录数，用于计算新增量
    final beforeMovements = await dbHelper.getAllMovements();
    final beforeCount = beforeMovements.length;
    int whAdded = 0;

    try {
      client = await _createClient();
      final creds = await _getCredentials();
      await client.connect(creds['username']!, creds['password']!);

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
          'MQTT 连接失败: ${client.connectionStatus?.returnCode}',
        );
      }

      client.subscribe(_snapshotTopic, MqttQos.atLeastOnce);

      final updates = client.updates;
      if (updates == null) {
        throw Exception('MQTT updates stream 不可用');
      }

      // 5 秒超时：云端如果没有 retain 快照，必须立刻失败而不是永远挂起
      final messages = await updates.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception(
          '云端尚未生成快照，或网络超时',
        ),
      );

      final recMess = messages[0];
      final pubMess = recMess.payload as MqttPublishMessage;
      final payloadString = utf8.decode(pubMess.payload.message);

      // 绝对安全的 JSON 解析，防止 Null is not a subtype 崩溃
      final Map<String, dynamic> data =
          jsonDecode(payloadString) as Map<String, dynamic>;
      final List<dynamic> recordsList = data['records'] as List<dynamic>? ?? [];
      final List<dynamic> warehousesList =
          data['warehouses'] as List<dynamic>? ?? [];

      // 1. 先写入 warehouses — 只添加不覆盖（本地优先）
      if (warehousesList.isNotEmpty) {
        for (final e in warehousesList) {
          if (e is! Map<String, dynamic>) continue;
          final wh = Warehouse.fromJson(e);
          await dbHelper.insertWarehouse(wh, conflictAlgorithm: ConflictAlgorithm.ignore);
          whAdded++;
        }
      }

      // 2. 再写入 records — 本地优先，只添加不删除不覆盖
      if (recordsList.isNotEmpty) {
        for (final e in recordsList) {
          if (e is! Map<String, dynamic>) continue;
          final record = StockMovement.fromJson(e);
          await dbHelper.insertMovement(record, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      // 拉取后统计，计算实际新增
      final afterMovements = await dbHelper.getAllMovements();
      final actualNew = afterMovements.length - beforeCount;

      client.unsubscribe(_snapshotTopic);
      return PullResult(
        success: true,
        addedCount: actualNew,
        warehouseCount: whAdded,
        message: actualNew > 0
            ? '成功从云端获取 $actualNew 条新记录'
            : '已与云端同步，暂无新数据',
      );
    } catch (e) {
      return PullResult(
        success: false,
        addedCount: 0,
        warehouseCount: 0,
        message: '拉取快照失败: $e',
      );
    } finally {
      client?.disconnect();
    }
  }
}
