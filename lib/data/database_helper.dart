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
  static const int _databaseVersion = 2;

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

  /// 数据库升级（v1 → v2）
  ///
  /// v1 仅有 transaction_records 表，v2 将其重构为 stock_movements 并新增 warehouses 表。
  /// 由于字段不兼容，旧表数据将被丢弃。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 删除旧版 transaction_records 表（如有）
      await db.execute('DROP TABLE IF EXISTS transaction_records');
      // 创建新版表
      await _createWarehousesTable(db);
      await _createStockMovementsTable(db);
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

  /// 创建库存移动记录表
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
  Future<int> insertWarehouse(Warehouse warehouse) async {
    final db = await database;
    return await db.insert(
      _warehousesTable,
      warehouse.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
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
  Future<int> insertMovement(StockMovement movement) async {
    final db = await database;
    return await db.insert(
      _movementsTable,
      movement.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查询所有记录（按时间倒序）
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

  /// 查询所有 pending 状态的记录（用于批量同步）
  Future<List<StockMovement>> getPendingMovements() async {
    final db = await database;
    final maps = await db.query(
      _movementsTable,
      where: 'syncStatus = ?',
      whereArgs: [SyncStatus.pending.name],
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
}
