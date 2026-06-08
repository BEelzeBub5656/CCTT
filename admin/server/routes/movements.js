const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { getDb, ALL_MOVEMENTS_BASE } = require('../db');
const { debouncedPublishSnapshot } = require('../mqtt');

// 写入操作后去抖发布快照（800ms 内合并多次操作）
function triggerSnapshot(label) {
  debouncedPublishSnapshot(label);
}

// 辅助：为记录添加计算字段
function enrich(row) {
  const qty = row.quantity || 0;
  return {
    ...row,
    totalAmount: Math.round((qty / 1000) * (row.unitPrice || 0) * 100) / 100,
    calculatedNetWeight: Math.round(((row.grossWeight || 0) - (row.tareWeight || 0)) * 100) / 100,
  };
}

// GET /api/movements — 带筛选、排序、分页的列表
router.get('/', (req, res) => {
  const db = getDb();
  const {
    warehouseId, type, syncStatus, search,
    startDate, endDate, includeDeleted,
    sortBy = 'timestamp', sortOrder = 'desc',
    page = '1', limit = '50',
  } = req.query;

  const conditions = [];
  const params = [];

  // 默认显示全部记录（含已作废），传 ?includeDeleted=false 才过滤
  if (includeDeleted === 'false') {
    conditions.push('m.isDeleted = 0');
  }

  if (warehouseId) {
    conditions.push('m.warehouseId = ?');
    params.push(warehouseId);
  }
  if (type) {
    conditions.push('m.type = ?');
    params.push(type);
  }
  if (syncStatus) {
    conditions.push('m.syncStatus = ?');
    params.push(syncStatus);
  }
  if (search) {
    conditions.push('(m.partnerName LIKE ? OR m.color LIKE ? OR m.variety LIKE ?)');
    const like = '%' + search + '%';
    params.push(like, like, like);
  }
  if (startDate) {
    conditions.push('m.timestamp >= ?');
    params.push(parseInt(startDate));
  }
  if (endDate) {
    conditions.push('m.timestamp <= ?');
    params.push(parseInt(endDate));
  }

  const where = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';

  // 允许的排序字段
  const allowedSorts = ['timestamp', 'quantity', 'unitPrice', 'grossWeight', 'partnerName', 'syncStatus'];
  const safeSortBy = allowedSorts.includes(sortBy) ? sortBy : 'timestamp';
  const safeSortOrder = sortOrder === 'asc' ? 'ASC' : 'DESC';
  const orderClause = `ORDER BY m.${safeSortBy} ${safeSortOrder}`;

  const pageNum = Math.max(1, parseInt(page) || 1);
  const limitNum = Math.min(200, Math.max(1, parseInt(limit) || 50));
  const offset = (pageNum - 1) * limitNum;

  // 总数
  const countSql = `SELECT COUNT(*) AS count FROM stock_movements m ${where}`;
  const total = db.prepare(countSql).get(...params).count;

  // 分页数据
  const dataSql = `
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    ${where}
    ${orderClause}
    LIMIT ? OFFSET ?
  `;
  const rows = db.prepare(dataSql).all(...params, limitNum, offset).map(enrich);

  res.json({
    data: rows,
    pagination: {
      page: pageNum,
      limit: limitNum,
      total,
      totalPages: Math.ceil(total / limitNum),
    },
  });
});

// GET /api/movements/:id — 单条详情
router.get('/:id', (req, res) => {
  const db = getDb();
  const row = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.id = ?
  `).get(req.params.id);

  if (!row) return res.status(404).json({ error: '记录不存在' });
  res.json(enrich(row));
});

// POST /api/movements — 创建记录
router.post('/', (req, res) => {
  const db = getDb();
  const b = req.body;

  // 仓库存在性校验
  if (!b.warehouseId) return res.status(400).json({ error: '请选择仓库' });
  const wh = db.prepare('SELECT id FROM warehouses WHERE id = ?').get(b.warehouseId);
  if (!wh) return res.status(400).json({ error: '所选仓库不存在' });

  // 交易对象必填
  if (!b.partnerName || !b.partnerName.trim()) return res.status(400).json({ error: '交易对象不能为空' });

  const id = b.id || uuidv4();
  const timestamp = b.timestamp || Date.now();
  const type = b.type === 'inbound' ? 'inbound' : 'outbound';

  // 净重计算：grossWeight - tareWeight
  const gross = parseFloat(b.grossWeight) || 0;
  const tare = parseFloat(b.tareWeight) || 0;
  const quantity = parseFloat(b.quantity) || (gross - tare);
  if (quantity <= 0) return res.status(400).json({ error: '净重必须大于 0' });

  const unitPrice = parseFloat(b.unitPrice) || 0;
  if (unitPrice < 0) return res.status(400).json({ error: '单价不能为负数' });

  db.prepare(`
    INSERT INTO stock_movements
      (id, timestamp, partnerName, warehouseId, type, quantity, unitPrice, syncStatus,
       color, variety, grossWeight, tareWeight, totalPieces, deliveryPerson, isDeleted)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, 0)
  `).run(
    id, timestamp, b.partnerName.trim(), b.warehouseId, type, quantity, unitPrice,
    b.color || '', b.variety || '', gross, tare,
    b.totalPieces ? parseInt(b.totalPieces) : null,
    b.deliveryPerson || null,
  );

  const row = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.id = ?
  `).get(id);

  res.status(201).json(enrich(row));

  // 自动更新云端快照
  triggerSnapshot('创建记录');
});

// PUT /api/movements/:id — 编辑记录（仅可编辑部分字段，匹配 Flutter EditRecordPage）
router.put('/:id', (req, res) => {
  const db = getDb();
  const existing = db.prepare('SELECT * FROM stock_movements WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: '记录不存在' });

  const b = req.body;

  // 安全数值转换（防止 null/NaN 污染数据库）
  function safeNum(val, fallback) {
    if (val === undefined || val === null || val === '') return fallback;
    const n = parseFloat(val);
    return isNaN(n) || !isFinite(n) ? fallback : n;
  }

  // 仅可编辑这些字段
  const grossWeight = safeNum(b.grossWeight, existing.grossWeight);
  const tareWeight = safeNum(b.tareWeight, existing.tareWeight);
  const unitPrice = safeNum(b.unitPrice, existing.unitPrice);
  const totalPieces = b.totalPieces !== undefined && b.totalPieces !== null ? parseInt(b.totalPieces) : existing.totalPieces;
  const deliveryPerson = b.deliveryPerson !== undefined ? b.deliveryPerson : existing.deliveryPerson;

  // 重新计算净重
  const quantity = grossWeight - tareWeight;
  if (isNaN(quantity) || quantity <= 0) return res.status(400).json({ error: '净重必须大于 0' });
  if (isNaN(unitPrice) || unitPrice < 0) return res.status(400).json({ error: '单价不能为负数' });

  // 编辑后重置同步状态为 pending
  db.prepare(`
    UPDATE stock_movements SET
      grossWeight = ?, tareWeight = ?, quantity = ?, unitPrice = ?,
      totalPieces = ?, deliveryPerson = ?, syncStatus = 'pending', timestamp = ?
    WHERE id = ?
  `).run(grossWeight, tareWeight, quantity, unitPrice, totalPieces, deliveryPerson, Date.now(), req.params.id);

  const row = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.id = ?
  `).get(req.params.id);

  res.json(enrich(row));

  // 自动更新云端快照
  triggerSnapshot('编辑记录');
});

// DELETE /api/movements/:id — 软删除
router.delete('/:id', (req, res) => {
  const db = getDb();
  const existing = db.prepare('SELECT * FROM stock_movements WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: '记录不存在' });
  if (existing.isDeleted) return res.status(400).json({ error: '记录已作废' });

  const voidReason = req.body.voidReason || null;
  db.prepare("UPDATE stock_movements SET isDeleted = 1, syncStatus = 'pending', voidReason = ?, timestamp = ? WHERE id = ?")
    .run(voidReason, Date.now(), req.params.id);

  const row = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.id = ?
  `).get(req.params.id);

  res.json(enrich(row));

  // 自动更新云端快照
  triggerSnapshot('软删除记录');
});

// DELETE /api/movements/:id/hard — 永久删除（彻底从数据库移除）
router.delete('/:id/hard', (req, res) => {
  const db = getDb();
  const existing = db.prepare('SELECT * FROM stock_movements WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: '记录不存在' });

  db.prepare('DELETE FROM stock_movements WHERE id = ?').run(req.params.id);
  res.json({ message: '记录已永久删除' });

  // 删完立即发布快照
  triggerSnapshot('永久删除记录');
});

// POST /api/movements/:id/restore — 恢复软删除记录
router.post('/:id/restore', (req, res) => {
  const db = getDb();
  const existing = db.prepare('SELECT * FROM stock_movements WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: '记录不存在' });
  if (!existing.isDeleted) return res.status(400).json({ error: '记录未被作废' });

  db.prepare("UPDATE stock_movements SET isDeleted = 0, syncStatus = 'pending', voidReason = NULL, timestamp = ? WHERE id = ?").run(Date.now(), req.params.id);

  const row = db.prepare(`
    SELECT m.*, w.name AS warehouseName
    FROM stock_movements m
    LEFT JOIN warehouses w ON m.warehouseId = w.id
    WHERE m.id = ?
  `).get(req.params.id);

  res.json(enrich(row));

  // 自动更新云端快照
  triggerSnapshot('恢复记录');
});

module.exports = router;
