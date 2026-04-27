const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../db');

// GET /api/warehouses — 全部仓库列表
router.get('/', (req, res) => {
  const db = getDb();
  const rows = db.prepare('SELECT * FROM warehouses ORDER BY name ASC').all();
  res.json(rows);
});

// GET /api/warehouses/:id — 单个仓库
router.get('/:id', (req, res) => {
  const db = getDb();
  const row = db.prepare('SELECT * FROM warehouses WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: '仓库不存在' });
  res.json(row);
});

// POST /api/warehouses — 创建仓库
router.post('/', (req, res) => {
  const { name } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: '仓库名称不能为空' });
  if (name.trim().length > 100) return res.status(400).json({ error: '仓库名称不能超过100个字符' });

  const db = getDb();
  const id = uuidv4();
  db.prepare('INSERT INTO warehouses (id, name) VALUES (?, ?)').run(id, name.trim());
  const row = db.prepare('SELECT * FROM warehouses WHERE id = ?').get(id);
  res.status(201).json(row);
});

// PUT /api/warehouses/:id — 更新仓库名称
router.put('/:id', (req, res) => {
  const { name } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: '仓库名称不能为空' });
  if (name.trim().length > 100) return res.status(400).json({ error: '仓库名称不能超过100个字符' });

  const db = getDb();
  const exists = db.prepare('SELECT id FROM warehouses WHERE id = ?').get(req.params.id);
  if (!exists) return res.status(404).json({ error: '仓库不存在' });

  db.prepare('UPDATE warehouses SET name = ? WHERE id = ?').run(name.trim(), req.params.id);
  const row = db.prepare('SELECT * FROM warehouses WHERE id = ?').get(req.params.id);
  res.json(row);
});

// DELETE /api/warehouses/:id — 删除仓库（外键保护）
router.delete('/:id', (req, res) => {
  const db = getDb();
  const exists = db.prepare('SELECT id FROM warehouses WHERE id = ?').get(req.params.id);
  if (!exists) return res.status(404).json({ error: '仓库不存在' });

  const refs = db.prepare(
    'SELECT COUNT(*) AS count FROM stock_movements WHERE warehouseId = ? AND isDeleted = 0'
  ).get(req.params.id);

  if (refs.count > 0) {
    return res.status(409).json({
      error: '该仓库下有 ' + refs.count + ' 条出入库记录，无法删除。请先清理记录或将记录迁移到其他仓库',
      movementCount: refs.count,
    });
  }

  db.prepare('DELETE FROM warehouses WHERE id = ?').run(req.params.id);
  res.json({ message: '仓库已删除' });
});

module.exports = router;
