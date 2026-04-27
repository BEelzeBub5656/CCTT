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
app.use('/api/sync', require('./routes/sync'));

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
});
