import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';

/// MQTT 同步服务
///
/// 负责将本地 [SyncStatus.pending] / [SyncStatus.failed] 的库存移动记录
/// 通过 MQTT over TLS 发布到 EMQX Broker。
class SyncService {
  static const _broker = 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
  static const _port = 8883;
  static const _username = 'BEelzeBub';
  static const _password = '20050805jycPP';
  static const _topic = 'cctt/sync/inbound';

  static Future<String> syncPendingRecords() async {
    final dbHelper = DatabaseHelper.instance;
    final allRecords = await dbHelper.getAllMovements();

    // 抓取 pending 或 failed 的记录（防止任何非 synced 状态卡住）
    final pendingRecords = allRecords
        .where((r) =>
            r.syncStatus == SyncStatus.pending ||
            r.syncStatus == SyncStatus.failed)
        .toList();

    if (pendingRecords.isEmpty) {
      return '当前没有需要同步的记录';
    }

    final ids = pendingRecords.map((e) => e.id).toList();

    // 1. 标记为 syncing
    await dbHelper.updateSyncStatus(ids, SyncStatus.syncing);

    // 2. 初始化 MQTT 客户端
    final clientId = const Uuid().v4();
    final client = MqttServerClient(_broker, clientId);
    client.port = _port;
    client.secure = true;
    client.setProtocolV311();
    client.logging(on: false);

    try {
      // 3. 连接 MQTT
      await client.connect(_username, _password);

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
        client.disconnect();
        return 'MQTT 连接失败: ${client.connectionStatus?.returnCode}';
      }

      // 4. 转换为 JSON 字符串
      final payload = jsonEncode(
        pendingRecords.map((e) => e.toJson()).toList(),
      );

      // 5. 发布到主题，QoS = 1 (At least once)
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      client.publishMessage(
        _topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      // 6. 立刻断开连接
      client.disconnect();

      // 7. 标记为 synced
      await dbHelper.updateSyncStatus(ids, SyncStatus.synced);
      return '成功同步 ${pendingRecords.length} 条记录';
    } catch (e) {
      // 异常回滚：状态复位为 failed
      await dbHelper.updateSyncStatus(ids, SyncStatus.failed);
      client.disconnect();
      return e.toString();
    }
  }
}
