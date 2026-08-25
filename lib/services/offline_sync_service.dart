import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/warehouse.dart';

/// 离线同步服务 - 无需服务器的数据导出/导入
///
/// 通过JSON文件实现设备间数据同步
class OfflineSyncService {
  /// 导出所有数据为JSON文件
  ///
  /// 返回导出的文件路径
  static Future<String> exportToJson() async {
    final db = DatabaseHelper.instance;

    // 1. 获取所有数据
    final warehouses = await db.getAllWarehouses();
    final orders = await db.getAllOrders();

    // 2. 打包所有Order及其明细和费用
    final ordersWithDetails = <Map<String, dynamic>>[];
    for (final order in orders) {
      final items = await db.getOrderItems(order.id);
      final fees = await db.getOrderFees(order.id);
      ordersWithDetails.add({
        'order': order.toJson(),
        'items': items.map((i) => i.toJson()).toList(),
        'fees': fees.map((f) => f.toJson()).toList(),
      });
    }

    // 3. 构建导出数据结构
    final exportData = {
      'version': 'v2.0',
      'exportTime': DateTime.now().millisecondsSinceEpoch,
      'warehouses': warehouses.map((w) => w.toJson()).toList(),
      'orders': ordersWithDetails,
    };

    // 4. 写入文件
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'CCTT_backup_$timestamp.json';
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsString(jsonEncode(exportData));

    return filePath;
  }

  /// 通过分享导出文件
  static Future<void> exportAndShare() async {
    final filePath = await exportToJson();
    await Share.shareXFiles([XFile(filePath)], text: 'CCTT数据备份');
  }

  /// 从JSON文件导入数据
  ///
  /// [filePath] 导入文件的路径
  /// [strategy] 冲突解决策略：'skip'(跳过), 'replace'(替换), 'merge'(合并-使用最新时间戳)
  ///
  /// 返回导入结果统计
  static Future<ImportResult> importFromJson(
    String filePath, {
    String strategy = 'merge',
  }) async {
    final db = DatabaseHelper.instance;

    // 1. 读取文件
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('文件不存在: $filePath');
    }

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    // 2. 验证版本
    final version = data['version'] as String?;
    if (version != 'v2.0') {
      throw Exception('不支持的数据版本: $version');
    }

    int warehousesAdded = 0;
    int warehousesSkipped = 0;
    int ordersAdded = 0;
    int ordersSkipped = 0;
    int ordersUpdated = 0;

    // 3. 导入仓库
    final warehousesList = data['warehouses'] as List<dynamic>? ?? [];
    for (final wJson in warehousesList) {
      if (wJson is! Map<String, dynamic>) continue;
      final warehouse = Warehouse.fromJson(wJson);
      final existing = await db.getWarehouseById(warehouse.id);

      if (existing == null) {
        await db.insertWarehouse(warehouse);
        warehousesAdded++;
      } else if (strategy == 'replace') {
        await db.insertWarehouse(warehouse);
        warehousesAdded++;
      } else {
        warehousesSkipped++;
      }
    }

    // 4. 导入订单
    final ordersList = data['orders'] as List<dynamic>? ?? [];
    for (final oData in ordersList) {
      if (oData is! Map<String, dynamic>) continue;

      final orderJson = oData['order'] as Map<String, dynamic>?;
      if (orderJson == null) continue;

      final order = Order.fromJson(orderJson);
      final itemsJson = (oData['items'] as List<dynamic>?) ?? [];
      final feesJson = (oData['fees'] as List<dynamic>?) ?? [];

      final existing = await db.getOrderById(order.id);

      if (existing == null) {
        // 新订单，直接插入
        await db.insertOrder(order);
        for (final iJson in itemsJson) {
          if (iJson is! Map<String, dynamic>) continue;
          await db.insertOrderItem(OrderItem.fromJson(iJson));
        }
        for (final fJson in feesJson) {
          if (fJson is! Map<String, dynamic>) continue;
          await db.insertOrderFee(OrderFee.fromJson(fJson));
        }
        ordersAdded++;
      } else {
        // 订单已存在，根据策略处理
        if (strategy == 'skip') {
          ordersSkipped++;
          continue;
        } else if (strategy == 'replace') {
          // 删除旧数据，写入新数据
          await _replaceOrder(db, order, itemsJson, feesJson);
          ordersUpdated++;
        } else if (strategy == 'merge') {
          // 使用最新时间戳的数据
          if (order.timestamp > existing.timestamp) {
            await _replaceOrder(db, order, itemsJson, feesJson);
            ordersUpdated++;
          } else {
            ordersSkipped++;
          }
        }
      }
    }

    return ImportResult(
      warehousesAdded: warehousesAdded,
      warehousesSkipped: warehousesSkipped,
      ordersAdded: ordersAdded,
      ordersUpdated: ordersUpdated,
      ordersSkipped: ordersSkipped,
    );
  }

  /// 替换订单及其明细和费用
  static Future<void> _replaceOrder(
    DatabaseHelper db,
    Order order,
    List<dynamic> itemsJson,
    List<dynamic> feesJson,
  ) async {
    // 删除旧明细和费用
    final oldItems = await db.getOrderItems(order.id);
    final oldFees = await db.getOrderFees(order.id);
    for (final item in oldItems) {
      await db.deleteOrderItem(item.id);
    }
    for (final fee in oldFees) {
      await db.deleteOrderFee(fee.id);
    }

    // 写入新数据
    await db.updateOrder(order);
    for (final iJson in itemsJson) {
      if (iJson is! Map<String, dynamic>) continue;
      await db.insertOrderItem(OrderItem.fromJson(iJson));
    }
    for (final fJson in feesJson) {
      if (fJson is! Map<String, dynamic>) continue;
      await db.insertOrderFee(OrderFee.fromJson(fJson));
    }
  }

  /// 获取导出文件列表
  static Future<List<File>> getExportFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory(directory.path);
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && f.path.contains('CCTT_backup_'))
        .toList();

    // 按修改时间倒序排列
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }
}

/// 导入结果统计
class ImportResult {
  final int warehousesAdded;
  final int warehousesSkipped;
  final int ordersAdded;
  final int ordersUpdated;
  final int ordersSkipped;

  ImportResult({
    required this.warehousesAdded,
    required this.warehousesSkipped,
    required this.ordersAdded,
    required this.ordersUpdated,
    required this.ordersSkipped,
  });

  int get totalWarehouseChanges => warehousesAdded;
  int get totalOrderChanges => ordersAdded + ordersUpdated;

  @override
  String toString() {
    return '仓库: +$warehousesAdded, 跳过$warehousesSkipped\n'
           '订单: +$ordersAdded, 更新$ordersUpdated, 跳过$ordersSkipped';
  }
}
