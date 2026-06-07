import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// SQLite 数据库辅助类（单例）
///
/// 管理 [warehouses] 和 [stock_movements] 两张表。
/// 支持多仓库库存管理，严格遵循 Offline-First 原则。
class DatabaseHelper {
  static const String _databaseName = 'cctt_database.db';
  static const int _databaseVersion = 6; // v6: 新增 imagePath 留档照片字段

  // 表名
  static const String _warehousesTable = 'warehouses';
  static const String _movementsTable = 'stock_movements';

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

  /// 创建库存移动记录表（v6，新增 imagePath 留档照片）
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
