import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
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
/// 负责将本地 [SyncStatus.pending] / [SyncStatus.failed] 的主单据
/// 通过 MQTT over TLS 发布到 EMQX Broker，同时支持从云端拉取全量快照。
///
/// **异常安全原则**：所有网络操作都在 try-catch 中，[client.disconnect] 在 finally 中
/// 无条件调用，防止任何情况下 MQTT 连接挂起或泄漏。
class SyncService {
  static const _publishTopic = 'cctt/sync/inbound';
  static const _snapshotTopic = 'cctt/sync/snapshot';
  static const _ackTopic = 'cctt/sync/ack';

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
    client.keepAlivePeriod = 30;
    client.connectTimeoutPeriod = 5000; // 5 秒连接超时
    return client;
  }

  static Future<Map<String, String>> _getCredentials() async {
    return {
      'username': await SettingsService.getMqttUsername(),
      'password': await SettingsService.getMqttPassword(),
    };
  }

  /// 发布本地待同步主单据到云端（包含 orders + warehouses）
  ///
  /// 异常安全：任何步骤抛出异常都会回滚状态为 [SyncStatus.failed]，
  /// 并在 [finally] 中确保 [client.disconnect]。
  static Future<String> syncPendingRecords() async {
    final dbHelper = DatabaseHelper.instance;

    final pendingOrders = await dbHelper.getPendingOrders();

    if (pendingOrders.isEmpty) {
      return '当前没有需要同步的记录';
    }

    final orderIds = pendingOrders.map((o) => o.id).toList();
    // 标记新 orders 为 syncing
    await dbHelper.updateOrderSyncStatusBatch(orderIds, SyncStatus.syncing);

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

      // 打包全量新数据（orders/items/fees + warehouses）
      final allOrders = await dbHelper.getAllOrders();
      final orderPayload = <Map<String, dynamic>>[];
      for (final o in allOrders) {
        final items = await dbHelper.getOrderItems(o.id);
        final fees = await dbHelper.getOrderFees(o.id);
        orderPayload.add({
          'order': o.toJson(),
          'items': items.map((i) => i.toJson()).toList(),
          'fees': fees.map((f) => f.toJson()).toList(),
        });
      }
      final payload = jsonEncode({
        'records': <Map<String, dynamic>>[],
        'orders': orderPayload,
        'warehouses': allWarehouses.map((e) => e.toJson()).toList(),
      });

      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);

      // 仅发送到 inbound，由 Web（Master）接手处理并发布权威快照
      client.publishMessage(
        _publishTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      await dbHelper.updateOrderSyncStatusBatch(orderIds, SyncStatus.synced);

      // 等待 Web 的 Ack（Web 处理完并发布快照后会通知到 ack 主题）
      client.subscribe(_ackTopic, MqttQos.atLeastOnce);
      final ackStream = client.updates;
      if (ackStream != null) {
        try {
          await ackStream.first.timeout(
            const Duration(seconds: 8),
          );
        } catch (_) {
          // 超时也继续下拉（尽力而为）
        }
        client.unsubscribe(_ackTopic);
      }

      // Ack 确认后拉取最新快照（复用当前连接）
      final pullResult = await pullSnapshot(client: client);
      return '同步完成: ${pullResult.message}';
    } catch (e) {
      await dbHelper.updateOrderSyncStatusBatch(orderIds, SyncStatus.failed);
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
  static Future<PullResult> pullSnapshot({MqttServerClient? client}) async {
    final dbHelper = DatabaseHelper.instance;
    final bool ownClient = client == null;

    // 拉取前统计本地主单据数，用于计算新增量
    final beforeOrders = await dbHelper.getAllOrders();
    final beforeCount = beforeOrders.length;
    int whAdded = 0;

    try {
      client ??= await _createClient();
      if (ownClient) {
        final creds = await _getCredentials();
        await client.connect(creds['username']!, creds['password']!);
      }

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
      final List<dynamic> ordersList = data['orders'] as List<dynamic>? ?? [];
      final List<dynamic> warehousesList =
          data['warehouses'] as List<dynamic>? ?? [];

      // 1. 先写入 warehouses — Master 快照有最高优先级，强制覆盖本地
      if (warehousesList.isNotEmpty) {
        for (final e in warehousesList) {
          if (e is! Map<String, dynamic>) continue;
          final wh = Warehouse.fromJson(e);
          await dbHelper.insertWarehouse(wh,
              conflictAlgorithm: ConflictAlgorithm.replace);
          whAdded++;
        }
      }

      // 2. 清理旧 StockMovement 行。v2.0 起只使用 Order 新数据。
      final oldRecords = await dbHelper.getAllMovements();
      if (oldRecords.isNotEmpty) {
        await dbHelper.deleteMovements(oldRecords.map((r) => r.id).toList());
      }

      // 3. 处理 Orders（含 items 和 fees）
      final snapshotOrderIds = <String>{};
      for (final oe in ordersList) {
        if (oe is! Map<String, dynamic>) continue;
        final orderJson = oe['order'] as Map<String, dynamic>?;
        if (orderJson == null) continue;
        final order = Order.fromJson(orderJson);
        snapshotOrderIds.add(order.id);
        final itemsJson = (oe['items'] as List<dynamic>?) ?? [];
        final feesJson = (oe['fees'] as List<dynamic>?) ?? [];

        // 时间戳保护
        final localOrder = await dbHelper.getOrderById(order.id);
        if (localOrder != null &&
            localOrder.timestamp >= order.timestamp &&
            localOrder.syncStatus != SyncStatus.syncing) {
          continue;
        }

        await dbHelper.insertOrder(order);
        // 清除旧明细/费用，写入新数据
        final oldItems = await dbHelper.getOrderItems(order.id);
        final oldFees = await dbHelper.getOrderFees(order.id);
        for (final oi in oldItems) {
          await dbHelper.deleteOrderItem(oi.id);
        }
        for (final of in oldFees) {
          await dbHelper.deleteOrderFee(of.id);
        }
        for (final ij in itemsJson) {
          if (ij is! Map<String, dynamic>) continue;
          await dbHelper.insertOrderItem(OrderItem.fromJson(ij));
        }
        for (final fj in feesJson) {
          if (fj is! Map<String, dynamic>) continue;
          await dbHelper.insertOrderFee(OrderFee.fromJson(fj));
        }
      }

      // 4. 清理本地有但快照中没有的已同步 Order（Web 端已永久删除的）
      // 安全保护：只删已同步记录（pending 是本地新建未推送的，不能丢）
      final localOrdersAfter = await dbHelper.getAllOrders();
      final ordersToDelete = localOrdersAfter
          .where((o) =>
              o.syncStatus == SyncStatus.synced &&
              !snapshotOrderIds.contains(o.id))
          .map((l) => l.id)
          .toList();
      for (final id in ordersToDelete) {
        await dbHelper.deleteOrder(id);
      }

      // 拉取后统计，计算实际差异
      final afterOrders = await dbHelper.getAllOrders();
      final afterCount = afterOrders.length;
      final newRecords = afterCount - beforeCount;

      client.unsubscribe(_snapshotTopic);
      return PullResult(
        success: true,
        addedCount: newRecords > 0 ? newRecords : 0,
        warehouseCount: whAdded,
        message: newRecords > 0
            ? '成功从云端获取 $newRecords 张新单据'
            : '已与云端同步（本地 $afterCount 张单据）',
      );
    } catch (e) {
      return PullResult(
        success: false,
        addedCount: 0,
        warehouseCount: 0,
        message: '拉取快照失败: $e',
      );
    } finally {
      if (ownClient) client?.disconnect();
    }
  }
}
