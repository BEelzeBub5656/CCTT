const express = require('express');
const router = express.Router();
const { getDb, ALL_MOVEMENTS_BASE } = require('../db');

// GET /api/stats — 仪表盘聚合数据
router.get('/', (req, res) => {
  const db = getDb();

  const totalMovements = db.prepare(
    'SELECT COUNT(*) AS count FROM stock_movements WHERE isDeleted = 0'
  ).get().count;

  const totalWarehouses = db.prepare(
    'SELECT COUNT(*) AS count FROM warehouses'
  ).get().count;

  const byType = {
    inbound: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE type = 'inbound' AND isDeleted = 0").get().count,
    outbound: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE type = 'outbound' AND isDeleted = 0").get().count,
  };

  const bySync = {
    pending: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE syncStatus = 'pending' AND isDeleted = 0").get().count,
    syncing: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE syncStatus = 'syncing' AND isDeleted = 0").get().count,
    synced: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE syncStatus = 'synced' AND isDeleted = 0").get().count,
    failed: db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE syncStatus = 'failed' AND isDeleted = 0").get().count,
  };

  const recentActivity = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.isDeleted = 0
    ORDER BY m.timestamp DESC
    LIMIT 10
  `).all().map(enrich);

  res.json({ totalMovements, totalWarehouses, movementsByType: byType, movementsBySyncStatus: bySync, recentActivity });
});

// 辅助：为记录添加计算字段
function enrich(row) {
  const qty = row.quantity || 0;
  return {
    ...row,
    totalAmount: (qty / 1000) * (row.unitPrice || 0),
    calculatedNetWeight: (row.grossWeight || 0) - (row.tareWeight || 0),
  };
}

module.exports = router;
