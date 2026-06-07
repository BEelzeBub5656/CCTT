// ── 同步设置 ──
import { api } from '../api.js';
import { esc } from './dashboard.js';

export async function renderSettings() {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'settings');
  });

  try {
    const [status, logs] = await Promise.all([
      api.get('/api/sync/status'),
      api.get('/api/sync/inbound-logs'),
    ]);

    main.innerHTML = `
      <div class="page-title">
        <i class="fa-solid fa-gear" style="color:var(--teal)"></i>
        同步设置
        <span class="sub">MQTT 状态 & 快照管理</span>
      </div>

      <div class="stats-grid" style="margin-bottom:24px">
        <div class="stat-card">
          <div class="stat-icon ${status.connected ? 'green' : ''}" style="background:${status.connected ? 'var(--green-bg)' : 'var(--red-bg)'};color:${status.connected ? 'var(--green)' : 'var(--red)'}">
            <i class="fa-solid fa-${status.connected ? 'link' : 'unlink'}"></i>
          </div>
          <div>
            <div class="stat-value" style="font-size:20px">${status.connected ? '已连接' : '未连接'}</div>
            <div class="stat-label">MQTT Broker</div>
          </div>
        </div>

        <div class="stat-card">
          <div class="stat-icon blue"><i class="fa-solid fa-clock"></i></div>
          <div>
            <div class="stat-value" style="font-size:20px">${status.lastSyncAt ? formatRelative(status.lastSyncAt) : '—'}</div>
            <div class="stat-label">最近同步</div>
          </div>
        </div>

        <div class="stat-card">
          <div class="stat-icon teal"><i class="fa-solid fa-download"></i></div>
          <div>
            <div class="stat-value" style="font-size:20px">${status.lastSyncCount || 0} 条</div>
            <div class="stat-label">最近同步记录数</div>
          </div>
        </div>
      </div>

      <!-- 快照发布 -->
      <div class="card" style="margin-bottom:24px">
        <div class="card-header">
          发布全量快照
        </div>
        <div class="card-body">
          <p style="color:var(--slate-500);font-size:14px;margin-bottom:16px">
            将数据库中的所有仓库和出入库记录打包发布到 MQTT 快照主题（retain）。
            Flutter App 可通过"拉取快照"按钮获取最新数据。
          </p>
          <button class="btn btn-primary" id="btnSnapshot" onclick="window.publishSnapshot()">
            <i class="fa-solid fa-cloud-arrow-up"></i> 发布快照
          </button>
          <span id="snapshotResult" style="margin-left:12px;font-size:14px"></span>
        </div>
      </div>

      <!-- 同步日志 -->
      <div class="card">
        <div class="card-header">
          <span>同步接收日志</span>
          <span style="font-size:13px;color:var(--slate-500);font-weight:400">最近 50 条</span>
        </div>
        <div class="table-wrap">
          ${logs.length ? `
            <table>
              <thead>
                <tr><th>时间</th><th>记录数</th><th>仓库数</th><th>状态</th><th>错误信息</th></tr>
              </thead>
              <tbody>
                ${logs.map(l => `
                  <tr>
                    <td style="white-space:nowrap;font-size:13px">${new Date(l.timestamp).toLocaleString('zh-CN')}</td>
                    <td>${l.recordCount}</td>
                    <td>${l.warehouseCount}</td>
                    <td>${l.success ? '<span class="badge badge-synced">成功</span>' : '<span class="badge badge-failed">失败</span>'}</td>
                    <td style="font-size:12px;color:var(--slate-500)">${esc(l.error||'—')}</td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
          ` : '<div class="empty-state"><i class="fa-solid fa-inbox"></i><p>暂无同步日志</p></div>'}
        </div>
      </div>
    `;
  } catch (e) {
    main.innerHTML = '<div class="empty-state"><i class="fa-solid fa-triangle-exclamation"></i><p>加载失败: ' + esc(e.message) + '</p></div>';
  }
}

// ── 全局函数 ──

window.publishSnapshot = async function() {
  const btn = document.getElementById('btnSnapshot');
  const result = document.getElementById('snapshotResult');
  btn.disabled = true;
  btn.innerHTML = '<div class="spinner" style="width:14px;height:14px;border-width:2px;display:inline-block"></div> 发布中...';
  result.textContent = '';

  try {
    const data = await api.post('/api/sync/publish-snapshot');
    result.textContent = data.message;
    window.showToast(data.message, 'success');
  } catch (e) {
    result.innerHTML = '<span style="color:var(--red)">' + esc(e.message) + '</span>';
    window.showToast(e.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i> 发布快照';
  }
};

function formatRelative(ts) {
  const diff = Date.now() - ts;
  const secs = Math.floor(diff / 1000);
  if (secs < 60) return secs + ' 秒前';
  const mins = Math.floor(secs / 60);
  if (mins < 60) return mins + ' 分钟前';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + ' 小时前';
  return Math.floor(hours / 24) + ' 天前';
}
