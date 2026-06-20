import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cctt/data/database_helper.dart';
import 'package:cctt/models/order.dart';
import 'package:cctt/models/stock_movement.dart';
import 'package:cctt/models/warehouse.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = join(await getDatabasesPath(), 'cctt_database.db');
    await deleteDatabase(dbPath);
  });

  test('fresh database creates Order schema immediately', () async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = rows.map((row) => row['name'] as String).toSet();

    expect(tableNames, contains('warehouses'));
    expect(tableNames, contains('orders'));
    expect(tableNames, contains('order_items'));
    expect(tableNames, contains('order_fees'));
  });

  test('failed orders are returned for retry', () async {
    final warehouse = Warehouse(name: '测试仓库');
    await DatabaseHelper.instance.insertWarehouse(warehouse);
    final order = Order(
      partnerName: '测试客户',
      warehouseId: warehouse.id,
      type: MovementType.outbound,
      timestamp: 1713331200000,
      syncStatus: SyncStatus.failed,
    );
    await DatabaseHelper.instance.insertOrder(order);

    final pendingOrders = await DatabaseHelper.instance.getPendingOrders();

    expect(pendingOrders.map((o) => o.id), contains(order.id));
  });
}
