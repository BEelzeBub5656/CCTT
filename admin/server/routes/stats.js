const express = require('express');
const router = express.Router();
const { getDb, ALL_MOVEMENTS_BASE } = require('../db');

// GET /api/stats — 仪表盘聚合数据
router.get('/', (req, res) => {
  const db = getDb();

  // 旧记录统计
  const totalMovements = db.prepare('SELECT COUNT(*) AS count FROM stock_movements WHERE isDeleted = 0').get().count;
  const oldInbound = db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE type = 'inbound' AND isDeleted = 0").get().count;
  const oldOutbound = db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE type = 'outbound' AND isDeleted = 0").get().count;
  const oldPending = db.prepare("SELECT COUNT(*) AS count FROM stock_movements WHERE syncStatus != 'synced' AND isDeleted = 0").get().count;

  // 新 Order 统计
  const totalOrders = db.prepare('SELECT COUNT(*) AS count FROM orders WHERE isDeleted = 0').get().count;
  const orderInbound = db.prepare("SELECT COUNT(*) AS count FROM orders WHERE type = 'inbound' AND isDeleted = 0").get().count;
  const orderOutbound = db.prepare("SELECT COUNT(*) AS count FROM orders WHERE type = 'outbound' AND isDeleted = 0").get().count;
  const orderSupply = db.prepare("SELECT COUNT(*) AS count FROM orders WHERE type = 'supply' AND isDeleted = 0").get().count;
  const orderPending = db.prepare("SELECT COUNT(*) AS count FROM orders WHERE syncStatus != 'synced' AND isDeleted = 0").get().count;
  const orderSynced = db.prepare("SELECT COUNT(*) AS count FROM orders WHERE syncStatus = 'synced' AND isDeleted = 0").get().count;

  const totalWarehouses = db.prepare('SELECT COUNT(*) AS count FROM warehouses').get().count;

  const byType = {
    inbound: oldInbound + orderInbound,
    outbound: oldOutbound + orderOutbound,
    supply: orderSupply,
  };

  const bySync = {
    pending: oldPending + orderPending,
    synced: totalMovements + totalOrders - oldPending - orderPending,
    syncing: 0, failed: 0,
  };

  // 最近活动：合并旧记录和新 Order
  const oldRecent = db.prepare(`SELECT m.*, w.name AS warehouseName, 'movement' as source FROM stock_movements m LEFT JOIN warehouses w ON m.warehouseId = w.id WHERE m.isDeleted = 0 ORDER BY m.timestamp DESC LIMIT 5`).all().map(enrich);
  const orderRecent = db.prepare(`SELECT o.*, w.name AS warehouseName, 'order' as source FROM orders o LEFT JOIN warehouses w ON o.warehouseId = w.id WHERE o.isDeleted = 0 ORDER BY o.timestamp DESC LIMIT 5`).all();

  const allRecent = [...oldRecent, ...orderRecent].sort((a, b) => b.timestamp - a.timestamp).slice(0, 10);

  res.json({
    totalMovements: totalMovements + totalOrders,
    totalWarehouses,
    movementsByType: byType,
    movementsBySyncStatus: bySync,
    recentActivity: allRecent,
  });
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
