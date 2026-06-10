import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// SQLite 数据库辅助类（单例）
///
/// 管理 [warehouses] 和 [stock_movements] 两张表。
/// 支持多仓库库存管理，严格遵循 Offline-First 原则。
class DatabaseHelper {
  static const String _databaseName = 'cctt_database.db';
  static const int _databaseVersion = 9; // v9: 新增 orders + order_items + order_fees 主单据架构

  // 表名
  static const String _warehousesTable = 'warehouses';
  static const String _movementsTable = 'stock_movements';
  static const String _ordersTable = 'orders';
  static const String _orderItemsTable = 'order_items';
  static const String _orderFeesTable = 'order_fees';

  // ------------------- 单例模式 -------------------
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Database? _database;

  /// 获取数据库实例（懒加载）
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库：确定路径、打开连接、创建/升级表
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 首次创建数据库时执行建表语句
  Future<void> _onCreate(Database db, int version) async {
    await _createWarehousesTable(db);
    await _createStockMovementsTable(db);
  }

  /// 数据库升级
  ///
  /// - v1 → v2：旧版 transaction_records 表被重构为 stock_movements + warehouses
  /// - v2 → v3：平滑添加毛厂出库单扩展字段（ALTER TABLE ADD COLUMN）
  /// - v3 → v4：拆分 productName → color + variety，不丢失任何数据
  /// - v4 → v5：新增 isDeleted 软删除字段（INTEGER DEFAULT 0）
  /// - v5 → v6：新增 imagePath 留档照片字段（TEXT，可为 NULL）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 删除旧版 transaction_records 表（如有）
      await db.execute('DROP TABLE IF EXISTS transaction_records');
      // 创建新版表
      await _createWarehousesTable(db);
      await _createStockMovementsTable(db);
    }

    if (oldVersion < 3) {
      // v2 → v3：为已存在的 stock_movements 表添加新列（nullable，兼容旧数据）
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN productName TEXT');
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN totalPieces INTEGER');
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN grossWeight REAL');
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN tareWeight REAL');
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN deliveryPerson TEXT');
    }

    if (oldVersion < 4) {
      // v3 → v4：新增 color / variety，productName 在模型层面废弃但数据库保留
      // SQLite 的 ALTER TABLE 无法删除列，因此旧 productName 列继续存在但不使用。
      // 新增列必须带 DEFAULT 值，以兼容现有行。
      await db.execute(
          "ALTER TABLE $_movementsTable ADD COLUMN color TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE $_movementsTable ADD COLUMN variety TEXT NOT NULL DEFAULT ''");
    }

    if (oldVersion < 5) {
      // v4 → v5：新增 isDeleted 软删除字段
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN isDeleted INTEGER NOT NULL DEFAULT 0');
    }

    if (oldVersion < 6) {
      // v5 → v6：新增 imagePath 留档照片字段（可空）
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN imagePath TEXT');
    }

    if (oldVersion < 7) {
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN voidReason TEXT');
    }

    if (oldVersion < 8) {
      await db.execute(
          "ALTER TABLE $_movementsTable ADD COLUMN isSettled INTEGER NOT NULL DEFAULT 0");
      await db.execute(
          'ALTER TABLE $_movementsTable ADD COLUMN remark TEXT');
    }

    if (oldVersion < 9) {
      await _createOrdersTable(db);
      await _createOrderItemsTable(db);
      await _createOrderFeesTable(db);
      // 迁移旧数据：每条 stock_movement → 1 order + 1 order_item
      await _migrateV9(db);
    }
  }

  /// 创建仓库表
  Future<void> _createWarehousesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_warehousesTable (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL
      )
    ''');
  }

  /// 创建库存移动记录表（v8）
  Future<void> _createStockMovementsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_movementsTable (
        id TEXT PRIMARY KEY NOT NULL,
        timestamp INTEGER NOT NULL,
        partnerName TEXT NOT NULL,
        warehouseId TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitPrice REAL NOT NULL,
        syncStatus TEXT NOT NULL,
        color TEXT NOT NULL DEFAULT '',
        variety TEXT NOT NULL DEFAULT '',
        grossWeight REAL,
        tareWeight REAL,
        totalPieces INTEGER,
        deliveryPerson TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        imagePath TEXT,
        voidReason TEXT,
        isSettled INTEGER NOT NULL DEFAULT 0,
        remark TEXT,
        FOREIGN KEY (warehouseId) REFERENCES $_warehousesTable(id)
          ON DELETE RESTRICT
      )
    ''');
    // 为常用查询字段创建索引，提升检索性能
    await db.execute('''
      CREATE INDEX idx_movements_warehouse ON $_movementsTable(warehouseId)
    ''');
    await db.execute('''
      CREATE INDEX idx_movements_sync ON $_movementsTable(syncStatus)
    ''');
  }

  /// 创建 orders 表（v9）
  Future<void> _createOrdersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_ordersTable (
        id TEXT PRIMARY KEY NOT NULL,
        partnerName TEXT NOT NULL,
        warehouseId TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        isDeleted INTEGER NOT NULL DEFAULT 0,
        isSettled INTEGER NOT NULL DEFAULT 0,
        remark TEXT,
        voidReason TEXT,
        FOREIGN KEY (warehouseId) REFERENCES $_warehousesTable(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_wh ON $_ordersTable(warehouseId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_sync ON $_ordersTable(syncStatus)');
  }

  /// 创建 order_items 表（v9）
  Future<void> _createOrderItemsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_orderItemsTable (
        id TEXT PRIMARY KEY NOT NULL,
        orderId TEXT NOT NULL,
        itemName TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitPrice REAL NOT NULL,
        grossWeight REAL DEFAULT 0,
        tareWeight REAL DEFAULT 0,
        totalPieces INTEGER,
        deliveryPerson TEXT,
        imagePath TEXT,
        sortOrder INTEGER DEFAULT 0,
        FOREIGN KEY (orderId) REFERENCES $_ordersTable(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_order ON $_orderItemsTable(orderId)');
  }

  /// 创建 order_fees 表（v9）
  Future<void> _createOrderFeesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_orderFeesTable (
        id TEXT PRIMARY KEY NOT NULL,
        orderId TEXT NOT NULL,
        feeName TEXT NOT NULL,
        amount REAL NOT NULL,
        remark TEXT,
        sortOrder INTEGER DEFAULT 0,
        FOREIGN KEY (orderId) REFERENCES $_ordersTable(id) ON DELETE CASCADE
      )
    ''');
  }

  /// v9 迁移：旧 stock_movements → orders + order_items
  Future<void> _migrateV9(Database db) async {
    final rows = await db.query(_movementsTable);
    if (rows.isEmpty) return;

    for (final m in rows) {
      // 检查是否已迁移
      final existing = await db.query(_ordersTable, where: 'id = ?', whereArgs: [m['id']], limit: 1);
      if (existing.isNotEmpty) continue;

      final itemName = [
        (m['color'] as String?) ?? '',
        (m['variety'] as String?) ?? '',
      ].where((s) => s.isNotEmpty).join(' ').trim();
      final fallback = (m['partnerName'] as String?) ?? '';

      await db.insert(_ordersTable, {
        'id': m['id'],
        'partnerName': m['partnerName'],
        'warehouseId': m['warehouseId'],
        'type': m['type'],
        'timestamp': m['timestamp'],
        'syncStatus': m['syncStatus'],
        'isDeleted': m['isDeleted'],
        'isSettled': m['isSettled'],
        'remark': m['remark'],
        'voidReason': m['voidReason'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await db.insert(_orderItemsTable, {
        'id': '${m['id']}_item',
        'orderId': m['id'],
        'itemName': itemName.isNotEmpty ? itemName : fallback,
        'quantity': m['quantity'],
        'unitPrice': m['unitPrice'],
        'grossWeight': m['grossWeight'],
        'tareWeight': m['tareWeight'],
        'totalPieces': m['totalPieces'],
        'deliveryPerson': m['deliveryPerson'],
        'imagePath': m['imagePath'],
        'sortOrder': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // =================== Order CRUD ===================

  Future<int> insertOrder(Order order) async {
    final db = await database;
    return db.insert(_ordersTable, order.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateOrder(Order order) async {
    final db = await database;
    return db.update(_ordersTable, order.toJson(), where: 'id = ?', whereArgs: [order.id]);
  }

  Future<Order?> getOrderById(String id) async {
    final db = await database;
    final maps = await db.query(_ordersTable, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Order.fromJson(maps.first);
  }

  Future<List<Order>> getAllOrders() async {
    final db = await database;
    final maps = await db.query(_ordersTable, orderBy: 'timestamp DESC');
    return maps.map((m) => Order.fromJson(m)).toList();
  }

  Future<List<Order>> getOrdersByWarehouse(String warehouseId) async {
    final db = await database;
    final maps = await db.query(_ordersTable, where: 'warehouseId = ?', whereArgs: [warehouseId], orderBy: 'timestamp DESC');
    return maps.map((m) => Order.fromJson(m)).toList();
  }

  Future<List<Order>> getPendingOrders() async {
    final db = await database;
    final maps = await db.query(_ordersTable,
      where: 'syncStatus = ? OR syncStatus = ?',
      whereArgs: [SyncStatus.pending.name, SyncStatus.syncing.name],
      orderBy: 'timestamp DESC');
    return maps.map((m) => Order.fromJson(m)).toList();
  }

  Future<int> updateOrderSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    return db.update(_ordersTable, {'syncStatus': status.name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateOrderSyncStatusBatch(List<String> ids, SyncStatus status) async {
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(_ordersTable, {'syncStatus': status.name}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: false);
  }

  Future<int> deleteOrder(String id) async {
    final db = await database;
    return db.delete(_ordersTable, where: 'id = ?', whereArgs: [id]);
  }

  // =================== OrderItem CRUD ===================

  Future<int> insertOrderItem(OrderItem item) async {
    final db = await database;
    return db.insert(_orderItemsTable, item.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateOrderItem(OrderItem item) async {
    final db = await database;
    return db.update(_orderItemsTable, item.toJson(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteOrderItem(String id) async {
    final db = await database;
    return db.delete(_orderItemsTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final db = await database;
    final maps = await db.query(_orderItemsTable, where: 'orderId = ?', whereArgs: [orderId], orderBy: 'sortOrder ASC');
    return maps.map((m) => OrderItem.fromJson(m)).toList();
  }

  // =================== OrderFee CRUD ===================

  Future<int> insertOrderFee(OrderFee fee) async {
    final db = await database;
    return db.insert(_orderFeesTable, fee.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateOrderFee(OrderFee fee) async {
    final db = await database;
    return db.update(_orderFeesTable, fee.toJson(), where: 'id = ?', whereArgs: [fee.id]);
  }

  Future<int> deleteOrderFee(String id) async {
    final db = await database;
    return db.delete(_orderFeesTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<OrderFee>> getOrderFees(String orderId) async {
    final db = await database;
    final maps = await db.query(_orderFeesTable, where: 'orderId = ?', whereArgs: [orderId], orderBy: 'sortOrder ASC');
    return maps.map((m) => OrderFee.fromJson(m)).toList();
  }

  // =================== OrderDetail 聚合视图 ===================

  Future<OrderDetail> getOrderDetail(String id) async {
    final order = await getOrderById(id);
    final items = order != null ? await getOrderItems(id) : <OrderItem>[];
    final fees = order != null ? await getOrderFees(id) : <OrderFee>[];
    return OrderDetail(order: order!, items: items, fees: fees);
  }

  // =================== Warehouses CRUD ===================

  /// 新增仓库
  Future<int> insertWarehouse(Warehouse warehouse, {ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.replace}) async {
    final db = await database;
    return await db.insert(
      _warehousesTable,
      warehouse.toJson(),
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  /// 查询所有仓库
  Future<List<Warehouse>> getAllWarehouses() async {
    final db = await database;
    final maps = await db.query(_warehousesTable, orderBy: 'name ASC');
    return maps.map((m) => Warehouse.fromJson(m)).toList();
  }

  /// 根据 ID 查询单个仓库
  Future<Warehouse?> getWarehouseById(String id) async {
    final db = await database;
    final maps = await db.query(
      _warehousesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Warehouse.fromJson(maps.first);
  }

  /// 删除仓库（若该仓库下有关联的 stock_movements，由于外键 ON DELETE RESTRICT，会抛出异常）
  Future<int> deleteWarehouse(String id) async {
    final db = await database;
    return await db.delete(
      _warehousesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =================== StockMovements CRUD ===================

  /// 插入一条库存移动记录
  ///
  /// [conflictAlgorithm] 默认 [ConflictAlgorithm.replace]（用于本地编辑覆盖）。
  /// 拉取云端快照时传 [ConflictAlgorithm.ignore]，确保本地数据不被覆盖（本地优先，只添加不删除）。
  Future<int> insertMovement(StockMovement movement, {ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.replace}) async {
    final db = await database;
    return await db.insert(
      _movementsTable,
      movement.toJson(),
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  /// 查询所有记录（按时间倒序），返回包含已删除记录，由 UI 层根据 isDeleted 渲染
  Future<List<StockMovement>> getAllMovements() async {
    final db = await database;
    final maps = await db.query(
      _movementsTable,
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => StockMovement.fromJson(m)).toList();
  }

  /// 查询指定仓库的所有记录
  Future<List<StockMovement>> getMovementsByWarehouse(String warehouseId) async {
    final db = await database;
    final maps = await db.query(
      _movementsTable,
      where: 'warehouseId = ?',
      whereArgs: [warehouseId],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => StockMovement.fromJson(m)).toList();
  }

  /// 查询所有待同步的记录（pending + syncing + 已删除的也需要同步到 PC 端），用于批量同步
  Future<List<StockMovement>> getPendingMovements() async {
    final db = await database;
    final maps = await db.query(
      _movementsTable,
      where: 'syncStatus = ? OR syncStatus = ?',
      whereArgs: [SyncStatus.pending.name, SyncStatus.syncing.name],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => StockMovement.fromJson(m)).toList();
  }

  /// 更新指定记录的同步状态
  Future<int> updateMovementSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    return await db.update(
      _movementsTable,
      {'syncStatus': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 更新一条库存移动记录（按 id 匹配）
  Future<int> updateMovement(StockMovement movement) async {
    final db = await database;
    return await db.update(
      _movementsTable,
      movement.toJson(),
      where: 'id = ?',
      whereArgs: [movement.id],
    );
  }

  /// 永久删除一条记录（按 id 匹配）
  Future<int> deleteMovement(String id) async {
    final db = await database;
    return await db.delete(_movementsTable, where: 'id = ?', whereArgs: [id]);
  }

  /// 批量永久删除记录
  Future<void> deleteMovements(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    await db.delete(_movementsTable, where: 'id IN ($placeholders)', whereArgs: ids);
  }

  /// 批量更新多条记录的同步状态
  ///
  /// 使用 SQLite [Batch] 减少事务往返，提升批量更新性能。
  /// 安全批量更新同步状态
  Future<void> updateSyncStatus(List<String> ids, SyncStatus status) async {
    final db = await database;
    Batch batch = db.batch();
    for (String id in ids) {
      batch.update(
        _movementsTable,
        {'syncStatus': status.name},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: false);
  }
}
