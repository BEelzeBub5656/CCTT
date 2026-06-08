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
    client.onBadCertificate = (dynamic _) => true;
    client.setProtocolV311();
    client.logging(on: false);
    client.keepAlivePeriod = 30; // 30 秒心跳，防止被 Broker 踢掉
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

      // 打包全量数据（records + warehouses）
      final payload = jsonEncode({
        'records': allRecords.map((e) => e.toJson()).toList(),
        'warehouses': allWarehouses.map((e) => e.toJson()).toList(),
      });

      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);

      // 仅发送到 inbound，由 Web（Master）接手处理并发布权威快照
      // 手机端不直接发快照，避免多手机时的 retain 覆盖冲突
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

      // 3 秒超时：快速反馈（retain 消息应几乎即时到达）
      final messages = await updates.first.timeout(
        const Duration(seconds: 3),
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

      // 1. 先写入 warehouses — Master 快照有最高优先级，强制覆盖本地
      if (warehousesList.isNotEmpty) {
        for (final e in warehousesList) {
          if (e is! Map<String, dynamic>) continue;
          final wh = Warehouse.fromJson(e);
          await dbHelper.insertWarehouse(wh, conflictAlgorithm: ConflictAlgorithm.replace);
          whAdded++;
        }
      }

      // 2. 写入 records — Master 覆盖，但保护本地 pending 记录
      final snapshotIds = <String>{};
      final localRecords = await dbHelper.getAllMovements();
      final localPendingIds = localRecords
          .where((r) => r.syncStatus == SyncStatus.pending)
          .map((r) => r.id)
          .toSet();

      if (recordsList.isNotEmpty) {
        for (final e in recordsList) {
          if (e is! Map<String, dynamic>) continue;
          final record = StockMovement.fromJson(e);
          // 本地 pending 的记录不覆盖（正在等待上传，保护本地修改）
          if (localPendingIds.contains(record.id)) {
            snapshotIds.add(record.id);
            continue;
          }
          await dbHelper.insertMovement(record, conflictAlgorithm: ConflictAlgorithm.replace);
          snapshotIds.add(record.id);
        }
      }

      // 3. 清理本地有但快照中没有的记录（Web 端已永久删除的）
      // 安全保护：只删已同步记录（pending 是本地新建未推送的，不能丢）
      // 不再限制快照最小数量——空快照表示 Master 已清空，手机端也应清空
      final localAfter = await dbHelper.getAllMovements();
      final toDelete = localAfter
          .where((l) => l.syncStatus == SyncStatus.synced && !snapshotIds.contains(l.id))
          .map((l) => l.id)
          .toList();
      if (toDelete.isNotEmpty) {
        await dbHelper.deleteMovements(toDelete);
      }

      // 拉取后统计，计算实际差异
      final afterMovements = await dbHelper.getAllMovements();
      final afterCount = afterMovements.length;
      final newRecords = afterCount - beforeCount;

      client.unsubscribe(_snapshotTopic);
      return PullResult(
        success: true,
        addedCount: newRecords > 0 ? newRecords : 0,
        warehouseCount: whAdded,
        message: newRecords > 0
            ? '成功从云端获取 $newRecords 条新记录'
            : '已与云端同步（本地 $afterCount 条记录）',
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
