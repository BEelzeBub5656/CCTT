const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../db');

// GET /api/orders — 带筛选、排序、分页的列表
router.get('/', (req, res) => {
  const db = getDb();
  const { warehouseId, type, syncStatus, search, startDate, endDate, includeDeleted, sortBy = 'timestamp', sortOrder = 'desc', page = '1', limit = '50' } = req.query;

  const conditions = [];
  const params = [];
  if (!includeDeleted || includeDeleted === 'false') conditions.push('o.isDeleted = 0');
  if (warehouseId) { conditions.push('o.warehouseId = ?'); params.push(warehouseId); }
  if (type) { conditions.push('o.type = ?'); params.push(type); }
  if (syncStatus) { conditions.push('o.syncStatus = ?'); params.push(syncStatus); }
  if (search) { conditions.push('(o.partnerName LIKE ?)'); params.push('%' + search + '%'); }
  if (startDate) { conditions.push('o.timestamp >= ?'); params.push(parseInt(startDate)); }
  if (endDate) { conditions.push('o.timestamp <= ?'); params.push(parseInt(endDate)); }

  const where = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
  const allowedSorts = { timestamp: 'o.timestamp', partnerName: 'o.partnerName', syncStatus: 'o.syncStatus' };
  const orderBy = allowedSorts[sortBy] || 'o.timestamp';
  const dir = sortOrder === 'asc' ? 'ASC' : 'DESC';
  const pageNum = Math.max(1, parseInt(page) || 1);
  const limitNum = Math.min(200, Math.max(1, parseInt(limit) || 50));
  const offset = (pageNum - 1) * limitNum;

  const count = db.prepare(`SELECT COUNT(*) as c FROM orders o ${where}`).get(...params).c;
  const rows = db.prepare(`
    SELECT o.*, w.name AS warehouseName FROM orders o
    LEFT JOIN warehouses w ON o.warehouseId = w.id ${where} ORDER BY ${orderBy} ${dir} LIMIT ? OFFSET ?
  `).all(...params, limitNum, offset);

  // 为每个 order 加载 items 和 fees 及合计
  const data = rows.map(o => {
    const items = db.prepare('SELECT * FROM order_items WHERE orderId = ? ORDER BY sortOrder').all(o.id);
    const fees = db.prepare('SELECT * FROM order_fees WHERE orderId = ? ORDER BY sortOrder').all(o.id);
    const itemTotal = items.reduce((s, i) => s + (i.quantity / 1000) * i.unitPrice, 0);
    const feeTotal = fees.reduce((s, f) => s + f.amount, 0);
    return { ...o, items, fees, itemTotal: Math.round(itemTotal * 100) / 100, feeTotal, totalAmount: Math.round((itemTotal + feeTotal) * 100) / 100 };
  });

  res.json({ data, pagination: { page: pageNum, limit: limitNum, total: count, totalPages: Math.ceil(count / limitNum) } });
});

// GET /api/orders/:id
router.get('/:id', (req, res) => {
  const db = getDb();
  const o = db.prepare(`SELECT o.*, w.name AS warehouseName FROM orders o LEFT JOIN warehouses w ON o.warehouseId = w.id WHERE o.id = ?`).get(req.params.id);
  if (!o) return res.status(404).json({ error: '单据不存在' });
  const items = db.prepare('SELECT * FROM order_items WHERE orderId = ? ORDER BY sortOrder').all(req.params.id);
  const fees = db.prepare('SELECT * FROM order_fees WHERE orderId = ? ORDER BY sortOrder').all(req.params.id);
  const itemTotal = items.reduce((s, i) => s + (i.quantity / 1000) * i.unitPrice, 0);
  const feeTotal = fees.reduce((s, f) => s + f.amount, 0);
  res.json({ ...o, items, fees, itemTotal: Math.round(itemTotal * 100) / 100, feeTotal, totalAmount: Math.round((itemTotal + feeTotal) * 100) / 100 });
});

module.exports = router;
