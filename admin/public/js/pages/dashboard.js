// ── 仪表盘 ──
import { api } from '../api.js';
import { store } from '../state.js';
import { formatDate } from './movements.js';

export async function renderDashboard() {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  try {
    const [stats, warehouses] = await Promise.all([
      api.get('/api/stats'),
      api.get('/api/warehouses'),
    ]);
    store.setState({ stats, warehouses });

    main.innerHTML = `
      <div class="page-title">
        <i class="fa-solid fa-chart-pie" style="color:var(--teal)"></i>
        仪表盘
        <span class="sub">数据总览</span>
      </div>

      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-icon teal"><i class="fa-solid fa-database"></i></div>
          <div>
            <div class="stat-value">${stats.totalMovements}</div>
            <div class="stat-label">出入库记录总数</div>
          </div>
        </div>

        <div class="stat-card">
          <div class="stat-icon green"><i class="fa-solid fa-warehouse"></i></div>
          <div>
            <div class="stat-value">${stats.totalWarehouses}</div>
            <div class="stat-label">仓库数量</div>
          </div>
        </div>

        <div class="stat-card">
          <div class="stat-icon amber"><i class="fa-solid fa-clock"></i></div>
          <div>
            <div class="stat-value">${stats.movementsBySyncStatus.pending + stats.movementsBySyncStatus.failed}</div>
            <div class="stat-label">待处理同步</div>
          </div>
        </div>

        <div class="stat-card">
          <div class="stat-icon blue"><i class="fa-solid fa-scale-balanced"></i></div>
          <div>
            <div class="stat-value">${stats.movementsByType.inbound} <span style="font-size:14px;color:var(--green)">入</span> / ${stats.movementsByType.outbound} <span style="font-size:14px;color:var(--red)">出</span></div>
            <div class="stat-label">入库 / 出库</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          最近活动
          <button class="btn btn-sm btn-outline" onclick="location.reload()"><i class="fa-solid fa-rotate"></i> 刷新</button>
        </div>
        <div class="table-wrap">
          ${stats.recentActivity.length ? renderRecentTable(stats.recentActivity) : '<div class="empty-state"><i class="fa-solid fa-inbox"></i><p>暂无记录</p></div>'}
        </div>
      </div>
    `;

    // 高亮当前导航
    document.querySelectorAll('.nav-link').forEach(a => {
      a.classList.toggle('active', a.getAttribute('data-route') === 'dashboard');
    });
  } catch (e) {
    main.innerHTML = `<div class="empty-state"><i class="fa-solid fa-triangle-exclamation"></i><p>加载失败：${e.message}</p></div>`;
  }
}

function renderRecentTable(records) {
  return `
    <table>
      <thead>
        <tr>
          <th>时间</th><th>类型</th><th>交易对象</th><th>颜色/品种</th>
          <th>仓库</th><th>净重(kg)</th><th>总金额(元)</th><th>同步</th>
        </tr>
      </thead>
      <tbody>
        ${records.map(r => `
          <tr>
            <td style="font-size:13px;white-space:nowrap">${formatDate(r.timestamp)}</td>
            <td>${typeBadge(r.type)}</td>
            <td><strong>${esc(r.partnerName)}</strong></td>
            <td>${esc(r.color||'-')} / ${esc(r.variety||'-')}</td>
            <td>${esc(r.warehouseName||'-')}</td>
            <td style="font-family:var(--font-mono)">${r.quantity.toFixed(1)}</td>
            <td style="font-family:var(--font-mono);font-weight:600">${r.totalAmount.toFixed(2)}</td>
            <td>${syncBadge(r.syncStatus)}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
}

// 共享辅助函数
export function typeBadge(type) {
  const labels = { inbound: '入库', outbound: '出库' };
  return `<span class="badge badge-${type}">${labels[type] || type}</span>`;
}

export function syncBadge(status) {
  const labels = { pending: '未同步', syncing: '正在同步', synced: '已同步', failed: '同步失败' };
  return `<span class="badge badge-${status}">${labels[status] || status}</span>`;
}

export function esc(s) {
  if (!s) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
