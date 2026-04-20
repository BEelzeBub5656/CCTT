import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import 'settings_service.dart';

/// MQTT 同步服务
///
/// 负责将本地 [SyncStatus.pending] / [SyncStatus.failed] 的库存移动记录
/// 通过 MQTT over TLS 发布到 EMQX Broker，同时支持从云端拉取全量快照。
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

    // 收集相关仓库
    final allWarehouses = await dbHelper.getAllWarehouses();
    final relatedWarehouseIds = pendingRecords.map((r) => r.warehouseId).toSet();
    final relatedWarehouses = allWarehouses
        .where((w) => relatedWarehouseIds.contains(w.id))
        .toList();

    final client = await _createClient();
    final creds = await _getCredentials();

    try {
      await client.connect(creds['username']!, creds['password']!);
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
        client.disconnect();
        return 'MQTT 连接失败: ${client.connectionStatus?.returnCode}';
      }

      // 打包 records + warehouses
      final payload = jsonEncode({
        'records': pendingRecords.map((e) => e.toJson()).toList(),
        'warehouses': relatedWarehouses.map((e) => e.toJson()).toList(),
      });

      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);
      client.publishMessage(
        _publishTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      client.disconnect();
      await dbHelper.updateSyncStatus(ids, SyncStatus.synced);
      return '成功同步 ${pendingRecords.length} 条记录';
    } catch (e) {
      await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
      client.disconnect();
      return e.toString();
    }
  }

  /// 从云端拉取 retain 全量快照并写入本地数据库
  ///
  /// 解析 JSON 后，先写入 warehouses（replace 自动覆盖），再写入 records。
  static Future<String> pullSnapshot() async {
    final dbHelper = DatabaseHelper.instance;
    final client = await _createClient();
    final creds = await _getCredentials();

    try {
      await client.connect(creds['username']!, creds['password']!);
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        client.disconnect();
        return 'MQTT 连接失败: ${client.connectionStatus?.returnCode}';
      }

      client.subscribe(_snapshotTopic, MqttQos.atLeastOnce);

      final updates = client.updates;
      if (updates == null) {
        client.disconnect();
        return 'MQTT updates stream 不可用';
      }
      final messages = await updates.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('等待快照超时，云端可能没有发布 retain 消息'),
      );

      final recMess = messages[0];
      final pubMess = recMess.payload as MqttPublishMessage;
      final payloadString = utf8.decode(pubMess.payload.message);

      final jsonMap = jsonDecode(payloadString) as Map<String, dynamic>;

      // 1. 先写入 warehouses
      final warehouseList = jsonMap['warehouses'] as List<dynamic>?;
      if (warehouseList != null) {
        for (final e in warehouseList) {
          final wh = Warehouse.fromJson(e as Map<String, dynamic>);
          await dbHelper.insertWarehouse(wh);
        }
      }

      // 2. 再写入 records
      final recordList = jsonMap['records'] as List<dynamic>?;
      int count = 0;
      if (recordList != null) {
        for (final e in recordList) {
          final record = StockMovement.fromJson(e as Map<String, dynamic>);
          await dbHelper.insertMovement(record);
          count++;
        }
      }

      client.unsubscribe(_snapshotTopic);
      client.disconnect();
      return '成功从云端恢复 $count 条记录（含 ${warehouseList?.length ?? 0} 个仓库）';
    } catch (e) {
      client.disconnect();
      return '拉取快照失败: $e';
    }
  }
}
