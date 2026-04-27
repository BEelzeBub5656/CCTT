const express = require('express');
const router = express.Router();
const { publishSnapshot, getConnectionState, getSyncEvents } = require('../mqtt');

// GET /api/sync/status — MQTT 订阅者连接状态
router.get('/status', (req, res) => {
  res.json(getConnectionState());
});

// POST /api/sync/publish-snapshot — 手动发布快照
router.post('/publish-snapshot', async (req, res) => {
  try {
    const result = await publishSnapshot();
    res.json({
      message: '快照发布成功：' + result.recordCount + ' 条记录，' + result.warehouseCount + ' 个仓库',
      ...result,
    });
  } catch (err) {
    res.status(500).json({ error: '快照发布失败: ' + err.message });
  }
});

// GET /api/sync/inbound-logs — 最近同步日志
router.get('/inbound-logs', (req, res) => {
  res.json(getSyncEvents());
});

module.exports = router;
