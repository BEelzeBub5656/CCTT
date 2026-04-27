const mqtt = require('mqtt');
const { getDb } = require('./db');

// 同步事件日志（内存，最近 50 条）
const syncEvents = [];
let connectionState = { connected: false, lastSyncAt: null, lastSyncCount: 0, error: null };

function logSyncEvent(recordCount, warehouseCount, success, error) {
  const entry = { timestamp: Date.now(), recordCount, warehouseCount, success, error: error || null };
  syncEvents.unshift(entry);
  if (syncEvents.length > 50) syncEvents.pop();
}

function getConnectionState() {
  return { ...connectionState };
}

function getSyncEvents() {
  return [...syncEvents];
}

// ── 数据写入辅助 ──

function upsertRecordsAndWarehouses(records, warehouses) {
  const db = getDb();
  const insertWh = db.prepare('INSERT OR REPLACE INTO warehouses (id, name) VALUES (?, ?)');
  const insertMovement = db.prepare(`
    INSERT OR REPLACE INTO stock_movements
      (id, timestamp, partnerName, warehouseId, type, quantity, unitPrice, syncStatus,
       color, variety, grossWeight, tareWeight, totalPieces, deliveryPerson, isDeleted)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const transaction = db.transaction(() => {
    for (const wh of warehouses) {
      if (!wh.id || !wh.name) continue;
      insertWh.run(wh.id, wh.name);
    }
    for (const rec of records) {
      if (!rec.id) continue;
      insertMovement.run(
        rec.id,
        rec.timestamp || Date.now(),
        rec.partnerName || '',
        rec.warehouseId || '',
        rec.type || 'outbound',
        rec.quantity || 0,
        rec.unitPrice || 0,
        'synced',
        rec.color || '',
        rec.variety || '',
        rec.grossWeight || 0,
        rec.tareWeight || 0,
        rec.totalPieces || null,
        rec.deliveryPerson || null,
        rec.isDeleted || 0,
      );
    }
  });

  transaction();
}

// ── 长连接订阅者 ──

function startSubscriber() {
  const broker = process.env.MQTT_BROKER || 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
  const port = parseInt(process.env.MQTT_PORT || '8883');
  const username = process.env.MQTT_USERNAME || 'BEelzeBub';
  const password = process.env.MQTT_PASSWORD || '20050805jycPP';
  const inboundTopic = process.env.MQTT_TOPIC_INBOUND || 'cctt/sync/inbound';

  const client = mqtt.connect({
    protocol: 'mqtts',
    host: broker,
    port,
    username,
    password,
    clientId: 'cctt-admin-' + Date.now(),
    rejectUnauthorized: false,
    reconnectPeriod: 5000,
    connectTimeout: 30000,
  });

  client.on('connect', () => {
    console.log('[MQTT] 订阅者已连接到', broker);
    connectionState.connected = true;
    connectionState.error = null;

    client.subscribe(inboundTopic, { qos: 1 }, (err) => {
      if (err) {
        console.error('[MQTT] 订阅失败:', err.message);
        connectionState.error = err.message;
      } else {
        console.log('[MQTT] 已订阅主题:', inboundTopic);
      }
    });
  });

  client.on('message', (topic, payload) => {
    try {
      const data = JSON.parse(payload.toString('utf8'));
      const records = Array.isArray(data.records) ? data.records : [];
      const warehouses = Array.isArray(data.warehouses) ? data.warehouses : [];

      upsertRecordsAndWarehouses(records, warehouses);

      connectionState.lastSyncAt = Date.now();
      connectionState.lastSyncCount = records.length;
      logSyncEvent(records.length, warehouses.length, true);

      console.log('[MQTT] 收到同步数据: ' + records.length + ' 条记录, ' + warehouses.length + ' 个仓库');
    } catch (err) {
      console.error('[MQTT] 消息解析失败:', err.message);
      logSyncEvent(0, 0, false, err.message);
    }
  });

  client.on('error', (err) => {
    console.error('[MQTT] 连接错误:', err.message);
    connectionState.connected = false;
    connectionState.error = err.message;
  });

  client.on('close', () => {
    console.log('[MQTT] 连接已关闭');
    connectionState.connected = false;
  });

  client.on('reconnect', () => {
    console.log('[MQTT] 正在重连...');
  });

  return client;
}

// ── 快照发布者（按需连接，发布 retain 消息后断开）──

function publishSnapshot() {
  return new Promise((resolve, reject) => {
    const db = getDb();
    const broker = process.env.MQTT_BROKER || 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
    const port = parseInt(process.env.MQTT_PORT || '8883');
    const username = process.env.MQTT_USERNAME || 'BEelzeBub';
    const password = process.env.MQTT_PASSWORD || '20050805jycPP';
    const snapshotTopic = process.env.MQTT_TOPIC_SNAPSHOT || 'cctt/sync/snapshot';

    const allWarehouses = db.prepare('SELECT * FROM warehouses ORDER BY name ASC').all();
    const allMovements = db.prepare('SELECT * FROM stock_movements ORDER BY timestamp DESC').all();

    const payload = JSON.stringify({
      records: allMovements.map(r => ({ ...r, isDeleted: r.isDeleted ? 1 : 0 })),
      warehouses: allWarehouses,
    });

    // 显式 UTF-8 编码，确保中文字符正确传输
    const payloadBuffer = Buffer.from(payload, 'utf8');

    const client = mqtt.connect({
      protocol: 'mqtts',
      host: broker,
      port,
      username,
      password,
      clientId: 'cctt-snapshot-' + Date.now(),
      rejectUnauthorized: false,
      connectTimeout: 15000,
      clean: true,
    });

    const timeout = setTimeout(() => {
      client.end(true);
      reject(new Error('快照发布超时（15 秒）'));
    }, 15000);

    client.on('connect', () => {
      client.publish(snapshotTopic, payloadBuffer, { qos: 1, retain: true }, (err) => {
        clearTimeout(timeout);
        client.end();
        if (err) {
          reject(err);
        } else {
          // 快照发布成功后，所有记录标记为"已同步给手机"
          db.prepare("UPDATE stock_movements SET syncStatus = 'synced'").run();
          console.log('[MQTT] 快照已发布: ' + allMovements.length + ' 条记录, ' + allWarehouses.length + ' 个仓库（全部标记为已同步）');
          resolve({
            recordCount: allMovements.length,
            warehouseCount: allWarehouses.length,
          });
        }
      });
    });

    client.on('error', (err) => {
      clearTimeout(timeout);
      client.end(true);
      reject(err);
    });
  });
}

module.exports = { startSubscriber, publishSnapshot, getConnectionState, getSyncEvents };
