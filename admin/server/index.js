require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { initialize } = require('./db');
const { startSubscriber } = require('./mqtt');

const app = express();
const PORT = parseInt(process.env.PORT || '3456');

// 初始化数据库
initialize();

// 中间件 — 强制 UTF-8 编码
app.use(cors());
app.use(express.json({ type: 'application/json' }));

// API 路由 — 确保 JSON 响应使用 UTF-8
app.use('/api', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  next();
});

// 静态文件（前端 SPA）
app.use(express.static(path.join(__dirname, '..', 'public')));

// API 路由
app.use('/api/warehouses', require('./routes/warehouses'));
app.use('/api/movements', require('./routes/movements'));
app.use('/api/stats', require('./routes/stats'));
app.use('/api/orders', require('./routes/orders'));
app.use('/api/sync', require('./routes/sync'));
app.use('/api/version', require('./routes/version'));
app.use('/api/app-update', require('./routes/app-update'));

// APK文件下载路由
app.use('/downloads', express.static(path.join(__dirname, '..', 'downloads')));

// SPA fallback — 所有非 API 路由返回 index.html
app.get('*', (req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'API 端点不存在' });
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// 统一错误处理
app.use((err, req, res, next) => {
  console.error('[ERROR]', req.method, req.path, err.message);
  const status = err.status || 500;
  res.status(status).json({
    error: err.message || '服务器内部错误',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
});

// 优雅关闭
function shutdown() {
  console.log('[CCTT-Admin] 正在关闭...');
  const { close } = require('./db');
  try { close(); } catch (e) { /* ignore */ }
  process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
process.on('unhandledRejection', (reason) => {
  console.error('[CCTT-Admin] 未处理的 Promise 拒绝:', reason);
});

// 定时清理：已作废超过 2 天的记录自动永久删除
function startAutoCleanup() {
  const { getDb } = require('./db');
  const { publishSnapshot } = require('./mqtt');

  const cleanup = () => {
    try {
      const db = getDb();
      const cutoff = Date.now() - 2 * 24 * 60 * 60 * 1000; // 2 天前
      const result = db.prepare('DELETE FROM stock_movements WHERE isDeleted = 1 AND timestamp < ?').run(cutoff);
      if (result.changes > 0) {
        console.log('[Cleanup] 自动清理 ' + result.changes + ' 条过期已作废记录');
        publishSnapshot().then(r => console.log('[Cleanup] 快照已同步'));
      }
    } catch (e) { /* 静默 */ }
  };

  setInterval(cleanup, 60 * 60 * 1000); // 每小时检查一次
  console.log('[Cleanup] 自动清理已启动（已作废超过2天自动删除）');
}

// 启动服务器
app.listen(PORT, () => {
  console.log('[CCTT-Admin] Web 管理系统已启动');
  console.log('[CCTT-Admin] 访问地址: http://localhost:' + PORT);
  console.log('[CCTT-Admin] 环境模式:', process.env.NODE_ENV || 'development');

  // 启动 MQTT 订阅者
  try {
    startSubscriber();
    console.log('[CCTT-Admin] MQTT 订阅者已启动');
  } catch (err) {
    console.error('[CCTT-Admin] MQTT 订阅者启动失败:', err.message);
  }

  // 启动自动清理
  startAutoCleanup();
});
