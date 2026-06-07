const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = path.join(__dirname, 'data', 'cctt_database.db');

let db;

function getDb() {
  if (!db) throw new Error('数据库未初始化');
  return db;
}

function initialize() {
  // 确保 data 目录存在
  const fs = require('fs');
  const dataDir = path.dirname(DB_PATH);
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

  db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  // warehouses 表
  db.exec(`
    CREATE TABLE IF NOT EXISTS warehouses (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL
    )
  `);

  // stock_movements 表（v5）
  db.exec(`
    CREATE TABLE IF NOT EXISTS stock_movements (
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
      FOREIGN KEY (warehouseId) REFERENCES warehouses(id) ON DELETE RESTRICT
    )
  `);

  // 索引
  db.exec(`CREATE INDEX IF NOT EXISTS idx_movements_warehouse ON stock_movements(warehouseId)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_movements_sync ON stock_movements(syncStatus)`);

  console.log('[DB] 数据库初始化完成:', DB_PATH);
  return db;
}

// 预编译语句缓存
const stmts = {};

function prep(name, sql) {
  if (!stmts[name]) stmts[name] = db.prepare(sql);
  return stmts[name];
}

// 所有记录查询（含仓库名 JOIN）
const ALL_MOVEMENTS_BASE = `
  SELECT m.*, w.name AS warehouseName
  FROM stock_movements m
  LEFT JOIN warehouses w ON m.warehouseId = w.id
`;

function close() {
  if (db) {
    db.close();
    db = null;
  }
}

module.exports = { getDb, initialize, prep, ALL_MOVEMENTS_BASE, close };
